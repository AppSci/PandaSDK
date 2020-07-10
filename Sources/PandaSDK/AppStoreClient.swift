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


class AppStoreClient: NSObject {
    
    var onPurchase: ((String) -> Void)?
    var onRestore: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    
    private var products: [String: SKProduct] = [:]
    private var activeRequests: Set<ProductRequest> = []
    
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
    
    func purchase(productId: String) {
        getProduct(with: productId) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.onError?(error)
            case .success(let product):
                let payment = SKPayment(product: product)
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
        for transaction in transactions {
            switch (transaction.transactionState) {
            case .purchased:
                complete(transaction: transaction)
                break
            case .failed:
                fail(transaction: transaction)
                break
            case .restored:
                restore(transaction: transaction)
                break
            case .deferred:
                break
            case .purchasing:
                break
            }
        }
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        pandaLog("Restore Error: \(error)")
        onError?(error)
    }
    
    func paymentQueue(_ queue: SKPaymentQueue, shouldAddStorePayment payment: SKPayment, for product: SKProduct) -> Bool {
        pandaLog("")
        return true
    }
    
    private func complete(transaction: SKPaymentTransaction) {
        let payment = transaction.payment
        pandaLog("Purchased: \(payment)")
        onPurchase?(payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
    }

    private func restore(transaction: SKPaymentTransaction) {
        let payment = transaction.original?.payment ?? transaction.payment
        pandaLog("Restored: \(payment)")
        onRestore?(payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
    }

    private func fail(transaction: SKPaymentTransaction) {
        let error = transaction.error ?? Errors.unknownStoreError
        pandaLog("Purchase Error: \(error)")
        onError?(error)
        SKPaymentQueue.default().finishTransaction(transaction)
    }

}
