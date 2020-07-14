//
//  ClientConfig.swift
//  PandaSDK
//
//  Created by Kuts on 07.07.2020.
//

import Foundation

struct ClientConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case productIds
        case serverUrl = "SERVER_URL"
        case serverDebugUrl = "SERVER_URL_DEBUG"
        case policyUrl = "POLICY_URL"
        case termsUrl = "TERMS_URL"
        case billingUrl = "BILLING_URL"
    }
    
    static let current = loadPlist(name: "PandaSDK-Info") ?? .default
    static let `default` = ClientConfig(productIds: nil, serverUrl: "", serverDebugUrl: "", policyUrl: "", termsUrl: "", billingUrl: "https://apps.apple.com/account/billing")
    
    static func loadPlist(name: String) -> ClientConfig? {
        let decoder = PropertyListDecoder()
        guard let pListFileUrl = Bundle.main.url(forResource: name, withExtension: "plist", subdirectory: ""),
            let data = try? Data(contentsOf: pListFileUrl),
            let config = try? decoder.decode(ClientConfig.self, from: data) else {
                return nil
        }
        return config
    }

    let productIds: [String]?
    
    let serverUrl: String
    let serverDebugUrl: String
    let policyUrl: String
    let termsUrl: String
    let billingUrl: String
}