//
//  PandaFacebookHelpers.swift
//  PandaSDK
//
//  Created by Oleksii Filobok on 17.05.2021.
//  Copyright © 2021 PandaSDK. All rights reserved.
//

import Foundation

public enum FacebookKey: String, Codable {
    case fbc
    case fbp
}

public typealias FacebookIds = [FacebookKey: String]

public extension FacebookIds {
    static func instance(with fbcValue: String?, fbpValue: String?) -> FacebookIds {
        var result: FacebookIds = [:]
        if let fbcValue = fbcValue {
            result[.fbc] = fbcValue
        }
        if let fbpValue = fbpValue {
            result[.fbp] = fbpValue
        }
        return result
    }
}
