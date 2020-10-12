//
//  AppStoreClient.swift
//  PandaSDK
//
//  Created by Kuts on 04.07.2020.
//

import Foundation
import StoreKit


class ProductRequest: NSObject, SKProductsRequestDelegate {
    
    fileprivate let productRequest: SKProductsRequest
    
    init(productIds: Set<String>) {
        productRequest = SKProductsRequest(productIdentifiers: productIds)
        super.init()
        productRequest.delegate = self
    }

    var onResponse: ((ProductRequest, SKProductsResponse)->Void)?
    var onError: ((ProductRequest, Error)->Void)?
    var onFinish: ((ProductRequest) -> Void)?
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        onResponse?(self, response)
    }
    
    func requestDidFinish(_ request: SKRequest) {
        onFinish?(self)
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        onError?(self, error)
    }
}

public struct PaymentSource {
    let screenId: String
    let screenName: String
}

class AppStoreClient: NSObject {
    
    struct Transactions: Codable {
        var transactions: Set<String>
        func contains(_ transactionId: String?) -> Bool {
            return transactionId.map {transactions.contains($0)} ?? false
        }
        
        mutating func insert(_ transactionId: String?) {
            guard let transactionId = transactionId else { return }
            transactions.insert(transactionId)
        }
    }
    
    var onPurchase: ((String, PaymentSource) -> Void)?
    var onRestore: (([String]) -> Void)?
    var onError: ((Error) -> Void)?
    var onShouldAddStorePayment: ((_ payment: SKPayment, _ product: SKProduct)-> Bool)?
    
    internal var products: [String: SKProduct] = [:]
    private var activeRequests: Set<ProductRequest> = []
    private var activePayments: [SKPayment: PaymentSource] = [:]
    let storage: Storage<Transactions>
    
    init(storage: Storage<Transactions>) {
        self.storage = storage
    }
    
    var canMakePayment:Bool {
      return SKPaymentQueue.canMakePayments()
    }
    
    func startObserving() {
        SKPaymentQueue.default().remove(self)
        SKPaymentQueue.default().add(self)
    }
    
    func stopObserving() {
        SKPaymentQueue.default().remove(self)
    }
    
    func fetchProducts(productIds: Set<String>, completion: @escaping (Result<[String: SKProduct], Error>) -> Void) {
        let request = ProductRequest(productIds: productIds)
        request.onResponse = {[weak self] _, response in
            if !response.invalidProductIdentifiers.isEmpty {
                pandaLog("Invalid Product Identifiers: \(response.invalidProductIdentifiers)")
            }
            let products = Dictionary(uniqueKeysWithValues: response.products.map{($0.productIdentifier, $0)})
            self?.products.merge(products, uniquingKeysWith: {_, new in new})
            completion(.success(products))
        }
        request.onFinish = {[weak self] request in
            self?.activeRequests.remove(request)
        }
        request.onError = {request, error in
            pandaLog("FetchProduct Error: \(error)")
            completion(.failure(error))
        }
        activeRequests.insert(request)
        request.productRequest.start()
    }
    
    func getProduct(with productId: String, completion: @escaping (Result<SKProduct, Error>) -> Void) {
        if let product = products[productId] {
            completion(.success(product))
            return
        }
        fetchProducts(productIds: [productId]) { result in
            completion(result.flatMap { products -> Result<SKProduct, Error> in
                guard let product = products[productId] else {
                    return .failure(Errors.invalidProductId(productId))
                }
                return .success(product)
            })
        }
    }
    
    func purchase(productId: String, source: PaymentSource) {
        getProduct(with: productId) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.onError?(error)
            case .success(let product):
                let payment = SKPayment(product: product)
                self?.activePayments[payment] = source
                SKPaymentQueue.default().add(payment)
            }
        }
        
    }
    
    func restore() {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
}

extension AppStoreClient: SKPaymentTransactionObserver {
    
    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        var processed = storage.fetch() ?? Transactions(transactions: [])
        var restored: [SKPaymentTransaction] = []
        for transaction in transactions {
            switch (transaction.transactionState) {
            case .purchased:
                if let source = activePayments[transaction.payment],
                    !processed.contains(transaction.transactionIdentifier) {
                    complete(transaction: transaction, source: source)
                } else {
                    SKPaymentQueue.default().finishTransaction(transaction)
                }
                processed.insert(transaction.transactionIdentifier)
                activePayments.removeValue(forKey: transaction.payment)
            case .failed:
                fail(transaction: transaction)
                activePayments.removeValue(forKey: transaction.payment)
            case .restored:
                if processed.contains(transaction.transactionIdentifier) {
                    SKPaymentQueue.default().finishTransaction(transaction)
                } else {
                    restored.append(transaction)
                }
            case .deferred:
                break
            case .purchasing:
                break
            @unknown default:
                break
            }
        }
        defer {
            storage.store(processed)
        }
        guard !restored.isEmpty else { return }
        restore(transactions: restored)
        restored.forEach { processed.insert($0.transactionIdentifier) }
    }
    
    internal func receiptBase64String() -> Result<String, Error> {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else {
            return .failure(Errors.message("Missing appStoreReceiptURL"))
        }
        do {
            return .success(try Data(contentsOf: appStoreReceiptURL).base64EncodedString())
        } catch {
            return .failure(error)
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        pandaLog("Restore Error: \(error)")
        onError?(error)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        pandaLog("ShouldAddStorePayment")
        return onShouldAddStorePayment?(payment,product) ?? false
    }
    
    private func complete(transaction: SKPaymentTransaction, source: PaymentSource) {
        let payment = transaction.payment
        pandaLog("Purchased: \(payment)")
        onPurchase?(payment.productIdentifier, source)
        SKPaymentQueue.default().finishTransaction(transaction)
    }

    private func restore(transactions: [SKPaymentTransaction]) {
        let payments = transactions.map { return $0.original?.payment ?? $0.payment }
        pandaLog("Restored: \(payments)")
        onRestore?(payments.map {$0.productIdentifier})
        transactions.forEach {SKPaymentQueue.default().finishTransaction($0)}
    }

    private func fail(transaction: SKPaymentTransaction) {
        let error = transaction.error ?? Errors.unknownStoreError
        pandaLog("Purchase Error: \(error)")
        onError?(error)
        SKPaymentQueue.default().finishTransaction(transaction)
    }

}
