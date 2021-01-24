//
//  PandaSDKTests.swift
//  PandaSDKTests
//
//  Created by Kuts on 25.12.2020.
//  Copyright © 2020 PandaSDK. All rights reserved.
//

import XCTest
import StoreKitTest
@testable import PandaSDK

class PandaSDKTests: XCTestCase {

    var session: SKTestSession!
    
    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "Simple")
        session.disableDialogs = true
        session.clearTransactions()
        Panda.shared.configure(apiKey: "9QBqG5Kcxyvo2F8Pzwz27xrPsf1miVZ6", isDebug: true) {  (status) in
            print("Configured: \(status)")
        }
        expectation(for: NSPredicate(block: { (_, _) in Panda.shared is Panda}),
                    evaluatedWith: nil)
        waitForExpectations(timeout: 5)
        guard let panda = (Panda.shared as? Panda) else {
            XCTAssert(false, "Panda is unconfigured")
            return
        }
        panda.verificationClient = LocalVerification()
    }

    override func tearDownWithError() throws {
        session = nil
        Panda.shared.onPurchase = nil
        Panda.shared.onError = nil
    }
    
    func testSimple() throws {
        var called = false
        Panda.shared.onPurchase = { result in
            print(result)
            called = true
        }
        Panda.shared.onError = { error in
            print(error)
            called = true
        }
        guard let panda = (Panda.shared as? Panda) else {
            XCTAssert(false, "Panda is unconfigured")
            return
        }
        panda.appStoreClient.clearProcessedStorage()
        panda.appStoreClient.purchase(productId: "com.test.simple.monthly", source: PaymentSource(screenId: "testId", screenName: "testName"))
        expectation(for: NSPredicate(block: { (_, _) in called }),
                    evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

}

enum TestErrors: Error {
    case notInitialized
    case receiptError(ReceiptStatus)
    case noSubscriptions
}

class LocalVerification: VerificationClient {
    
    func verifySubscriptions(user: PandaUser, receipt: String, source: PaymentSource?, retries: Int, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        let certificate = Certificate(url: Bundle(for: type(of: self).self).url(forResource: "StoreKitTestCertificate", withExtension: "cer"), root: false)
        let receipt = Receipt(certificate: certificate)
        guard let status = receipt.receiptStatus else {
            callback(.failure(TestErrors.notInitialized))
            return
        }
        guard status == .validationSuccess else {
            callback(.failure(TestErrors.receiptError(status)))
            return
        }
        let now = Date()
        let subscriptions = receipt.inAppReceipts.compactMap { iap -> ReceiptVerificationResult? in
            guard
                let id = iap.productIdentifier,
                let expiration = iap.subscriptionExpirationDate else {
                return nil
            }
            return ReceiptVerificationResult(id: id, active: now < expiration)
        }
        guard let subscription = subscriptions.first(where: {$0.active}) ?? subscriptions.last(where: {!$0.active}) else {
            callback(.failure(TestErrors.noSubscriptions))
            return
        }
        callback(.success(subscription))
    }
}

