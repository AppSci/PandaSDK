//
//  WeakObject.swift
//  PandaSDK
//
//  Created by Kuts on 04.07.2020.
//

import Foundation

enum SubscriptionType: String, Codable {
    case ios
    case android
    case web
}

internal struct SubscriptionStatusResponse: Encodable {
    let state: SubscriptionAPIStatus
    let date: Date
    let subscriptions: [SubscriptionType: [SubscriptionInfo]]
    
    enum CodingKeys: String, CodingKey {
        case state
        case date
        case subscriptions
    }
}

extension SubscriptionStatusResponse: Decodable {

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(SubscriptionAPIStatus.self, forKey: CodingKeys.state)
        let dateInt = try container.decode(Int.self, forKey: CodingKeys.date)
        date  = Date(timeIntervalSince1970: TimeInterval(dateInt))
        let stringDictionary = try container.decode([String: [SubscriptionInfo]].self, forKey: CodingKeys.subscriptions)
        
        let sequence = stringDictionary.compactMap { keyValue -> (SubscriptionType, [SubscriptionInfo])? in
            guard let key = SubscriptionType(rawValue: keyValue.key) else {
                print("Unknown key: \(keyValue.key)")
                return nil
            }
            return (key, keyValue.value)
        }
        subscriptions = Dictionary(sequence, uniquingKeysWith: {l, _ in l})
    }

}

internal struct SubscriptionInfo: Codable {
    let productID: String
    let isTrial: Bool
    let price: Double?
    let state: SubscriptionAPIStatus
    
    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case isTrial  = "is_trial_period"
        case price
        case state
    }
}
