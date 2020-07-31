//
//  KeyChainAccess.swift
//  PandaSDK
//
//  Created by Kuts on 31.07.2020.
//

import Foundation

class KeyChainAccess {
    class func save(service: String, key: String, data: Data) {
        let keychainQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(keychainQuery as CFDictionary)
        SecItemAdd(keychainQuery as CFDictionary, nil)
    }

    class func load(service: String, key: String) -> Data? {
        let keychainQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?

        SecItemCopyMatching(keychainQuery as CFDictionary, &dataTypeRef)
        return dataTypeRef as? Data
    }
    
    class func clear(service: String, key: String) {
        let keychainQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(keychainQuery as CFDictionary)
    }

}
