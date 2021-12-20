//
//  CapiConfig.swift
//  PandaSDK
//
//  Created by Aleksey Filobok on 30.11.2021.
//

import Foundation

internal struct CAPIConfig: Codable, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.email ?? "" == rhs.email &&
        lhs.facebookLoginId ?? "" == rhs.email &&
        lhs.firstName ?? "" == rhs.firstName &&
        lhs.lastName ?? "" == rhs.lastName &&
        lhs.username ?? "" == rhs.username &&
        lhs.phone ?? "" == rhs.phone &&
        lhs.gender ?? 0 == rhs.gender
    }
    
    var email: String?
    var facebookLoginId: String?
    var firstName: String?
    var lastName: String?
    var username: String?
    var phone: String?
    var gender: Int?
    
    var requestDictionary: [String: String] {
        var result: [String: String] = [:]
        if let email = email {
            result["email"] = email
        }
        if let facebookId = facebookLoginId {
            result["facebook_login_id"] = facebookId
        }
        if let firstName = firstName {
            result["first_name"] = firstName
        }
        if let lastName = lastName {
            result["last_name"] = lastName
        }
        if let username = username {
            result["full_name"] = username
        }
        if let phone = phone {
            result["phone"] = phone
        }
        
        return result
    }
    
    mutating func updated(with other: CAPIConfig) -> CAPIConfig {
        if let email = other.email, email != self.email {
            self.email = email
        }
        if let facebookId = other.facebookLoginId, facebookId != self.facebookLoginId {
            self.facebookLoginId = facebookId
        }
        if let firstName = other.firstName, firstName != self.firstName {
            self.firstName = firstName
        }
        if let lastName = other.lastName, lastName != self.lastName {
            self.lastName = lastName
        }
        if let username = other.username, username != self.username {
            self.username = username
        }
        if let phone = other.phone, phone != self.phone {
            self.phone = phone
        }
        if let gender = other.gender, gender != self.gender {
            self.gender = gender
        }
        
        return self
    }
}
