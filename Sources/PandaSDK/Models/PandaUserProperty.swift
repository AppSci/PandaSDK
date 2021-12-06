//
//  PandaUserProperty.swift
//  PandaSDK
//
//  Created by Aleksey Filobok on 30.11.2021.
//

import Foundation

public struct PandaUserProperty: Hashable, Codable {
    public let key: String
    public let value: String
    
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.key)
    }
    
    public init(
        key: String,
        value: String
    ) {
        self.key = key
        self.value = value
    }
}
