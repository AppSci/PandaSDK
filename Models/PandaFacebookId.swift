//
//  PandaFacebookHelpers.swift
//  PandaSDK
//
//  Created by Oleksii Filobok on 17.05.2021.
//  Copyright © 2021 PandaSDK. All rights reserved.
//

import Foundation

public enum PandaFacebookId: Codable, Equatable {
    case fbc(value: String)
    case fbp(value: String)
    case fbpAndFbc(fbp: String, fbc: String)
    case empty
    
    public static func from(fbp: String?, fbc: String?) -> Self {
        if let fbc = fbc, let fbp = fbp {
            return .fbpAndFbc(fbp: fbp, fbc: fbc)
        }
        
        if let fbc = fbc {
            return .fbc(value: fbc)
        }
        
        if let fbp = fbp {
            return .fbp(value: fbp)
        }
        
        return .empty
    }
    
    var requestParameters: [String: String] {
        switch self {
        case .fbc(let value): return ["fbc": value]
        case .fbp(let value): return ["fbp": value]
        case .fbpAndFbc(let fbp, let fbc):
            return [
                "fbc": fbc,
                "fbp": fbp
            ]
        case .empty: return [:]
        }
    }
}
