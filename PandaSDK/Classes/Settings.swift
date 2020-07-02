//
//  Settings.swift
//  Panda
//
//  Created by Kuts on 29.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
class Settings {
    
    static let current = Settings()
    
    /// settings from plist
    lazy var config: [String: String] = readSettings()
    
    var webUrl: String {
        get {
            return config["WEB_URL"] ?? ""
        }
    }
    
    var serverUrl: String {
        get {
            return config["SERVER_URL"] ?? ""
        }
    }
    
    var serverDebugUrl: String {
        get {
            return config["SERVER_URL_DEBUG"] ?? ""
        }
    }
    
    var policyUrl: String {
        get {
            return config["POLICY_URL"] ?? ""
        }
    }
    
    var termsUrl: String {
        get {
            return config["TERMS_URL"] ?? ""
        }
    }
    
    var billingUrl: String {
        get {
            return config["BILLING_URL"] ?? "https://apps.apple.com/account/billing"
        }
    }
    
    var productID: String {
        get {
            return config["PRODUCT_ID"] ?? ""
        }
    }
    
    var functionsDomain: String? {
        get {
            return config["FUNCTIONS_DOMAIN"]
        }
    }
    
    private func readSettings() -> [String: String] {
        guard let path = Bundle.main.path(forResource: "SubscriptionBooster", ofType: "plist") else {
            return [:]
        }
        guard let settings = NSDictionary(contentsOfFile: path) as? [String: String] else {
            return [:]
        }
        return settings
    }
    
}
