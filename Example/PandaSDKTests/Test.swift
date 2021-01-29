//
//  Test.swift
//  PandaSDKTests
//
//  Created by Kuts on 29.01.2021.
//  Copyright © 2021 PandaSDK. All rights reserved.
//

import Foundation
import XCTest
@testable import PandaSDK

class PandaSDKResponseTests: XCTestCase {
    
    func testResponse() {
        let decoder =  JSONDecoder()
        let data = try! Data(contentsOf: Bundle(for: type(of: self).self).url(forResource: "response", withExtension: "json")!)
        let reponse = try! decoder.decode(SubscriptionStatusResponse.self, from: data)
        print(reponse)
    }
    
}
