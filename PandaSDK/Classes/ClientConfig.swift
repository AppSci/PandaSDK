//
//  ClientConfig.swift
//  PandaSDK
//
//  Created by Kuts on 07.07.2020.
//

import Foundation

struct ClientConfig: Codable {
    static let current = loadPlist(name: "PandaSDK-Info") ?? .default
    static let `default` = ClientConfig(productIds: nil)
    
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
    
}
