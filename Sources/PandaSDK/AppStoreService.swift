//
//  AppStoreService.swift
//  
//
//  Created by Denys Danyliuk on 29.08.2023.
//

import StoreKit

final class AppStoreService: NSObject {
    private var products: [String: Product] = [:]
    private var task: Task<Void, Error>?
    private var testTask: Task<Void, Error>?
    private let verificationClient: VerificationClient
    private var purchasing: Bool = false
    
    var onVerify: (() async -> Void)?
    
    init(verificationClient: VerificationClient) {
        self.verificationClient = verificationClient
         
        super.init()
    }
    
    deinit {
        task?.cancel()
    }
    
    func startTask() {
        task = Task {
            for await transactions in debounceCollect(Transaction.updates, for: 2) {
                guard !purchasing else {
                    return
                }
                await onVerify?()
                for verifiedTransaction in transactions {
                    guard let transaction = try? verifiedTransaction.payloadValue else {
                        return
                    }
                    await transaction.finish()
                }
            }
        }
        
        // Subscribe to shouldAddStorePayment
        SKPaymentQueue.default().add(self)
    }
    
    func restore() async throws {
        try await AppStore.sync()
    }
    
    func fetchProducts(productIDs: Set<String>, completion: @escaping (Result<[Product], Error>) -> Void) {
        Task { [weak self] in
            do {
                let storeProducts = try await Product.products(for: productIDs)
                for product in storeProducts {
                    self?.products[product.id] = product
                }
                completion(.success(storeProducts))
            } catch {
                pandaLog("FetchProduct Error: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func receiptBase64String() throws -> String {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else {
            throw Errors.message("Missing appStoreReceiptURL")
        }
        do {
            return try Data(contentsOf: appStoreReceiptURL).base64EncodedString()
        } catch {
            throw Errors.appStoreReceiptError(error)
        }
    }

    func purchase(productID: String, source: PaymentSource) async throws -> PurchaseResult {
        defer { purchasing = false }
        purchasing = true
        let product = try await getProduct(with: productID)
        let result = try await product.purchase(options: [
            .simulatesAskToBuyInSandbox(false)
        ])
        
        switch result {
        case let .success(verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            return .success(transaction, product)
            
        case .userCancelled:
            return .cancelled
            
        case .pending:
            return .pending
            
        @unknown default:
            return .pending
        }
    }
    
    func verifyTransaction(user: PandaUser, source: PaymentSource?) async throws -> ReceiptVerificationResult {
        let refresher = AppStoreReceiptRefresher()
        try? await refresher.refresh()
        let receipt = try receiptBase64String()
        
        let verification = try await verificationClient.verifySubscriptions(
            user: user,
            receipt: receipt,
            source: source,
            retries: 1
        )
        /// Wait until panda process receipt.
        try await Task.sleep(seconds: 3)
        return verification
    }
    
    func getProducts(with productIDs: [String]) async throws -> [Product] {
        var result: [Product] = []
        for productID in productIDs {
            result.append(try await getProduct(with: productID))
        }
        return result
    }
    
    func getProduct(with productID: String) async throws -> Product {
        if let product = products[productID] {
            return product
        } else if let product = try await Product.products(for: [productID]).first(where: { $0.id == productID }) {
            return product
        } else {
            throw Errors.invalidProductId(productID)
        }
    }
    
    func hideTrial(for products: [Product]) async -> Bool {
        for product in products {
            let isEligibleForIntroOffer = await product.subscription?.isEligibleForIntroOffer ?? false
            if !isEligibleForIntroOffer {
                return true
            }
        }
        return false
    }    
}

/// https://developer.apple.com/documentation/storekit/skpaymenttransactionobserver/promoting_in-app_purchases
extension AppStoreService: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) { }
    
    func paymentQueue(
        _ queue: SKPaymentQueue,
        shouldAddStorePayment payment: SKPayment,
        for product: SKProduct
    ) -> Bool {
        return Panda.shared.shouldAddStorePayment?(product) ?? false
    }
}

final class AppStoreReceiptRefresher: NSObject {
    private var continuation: CheckedContinuation<Void, Error>?
    
    func refresh() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let request = SKReceiptRefreshRequest()
            request.delegate = self
            request.start()
            self.continuation = continuation
        }
    }
}

extension AppStoreReceiptRefresher: SKRequestDelegate {
    func requestDidFinish(_ request: SKRequest) {
        continuation?.resume()
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
    }
}

