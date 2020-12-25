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
        panda.appStoreClient.purchase(productId: "com.test.simple.monthly", source: PaymentSource(screenId: "testId", screenName: "testName"))
        expectation(for: NSPredicate(block: { (_, _) in called }),
                    evaluatedWith: nil)
        waitForExpectations(timeout: 5)
    }

}

enum TestErrors: String, Error {
    case notInitialized
}

class LocalVerification: VerificationClient {
    
    func verifySubscriptions(user: PandaUser, receipt: String, source: PaymentSource?, retries: Int, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        callback(.success(ReceiptVerificationResult(id: "com.test.simple.monthly", active: true)))
    }
}

