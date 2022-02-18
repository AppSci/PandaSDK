//
//  WeakObject.swift
//  PandaSDK
//
//  Created by Kuts on 04.07.2020.
//

import Foundation

public enum SubscriptionType: String, Codable {
    case ios
    case android
    case web
}

internal struct SubscriptionStatusResponse: Encodable {
    let state: SubscriptionAPIStatus
    let date: Date?
    let subscriptions: [SubscriptionType: [SubscriptionInfo]]?
    
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
        let dateString = try container.decodeIfPresent(String.self, forKey: CodingKeys.date)
        date = dateString.flatMap { Int($0) }.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
 
        let stringDictionary = try container.decodeIfPresent([String: [SubscriptionInfo]].self, forKey: CodingKeys.subscriptions)
        
        let sequence = stringDictionary?.compactMap { keyValue -> (SubscriptionType, [SubscriptionInfo])? in
            guard let key = SubscriptionType(rawValue: keyValue.key) else {
                pandaLog("Unknown key: \(keyValue.key)")
                return nil
            }
            return (key, keyValue.value)
        }
        subscriptions = sequence.map { Dictionary($0, uniquingKeysWith: {l, _ in l}) }
    }

}

public struct SubscriptionInfo: Codable {
    public let productID: String
    public let isTrial: Bool
    public let isIntro: Bool?
    public let price: Double?
    public let state: SubscriptionAPIStatus
    public let paymentType: PaymentType
    
    public var stateDescription: String {
        state.rawValue
    }
    
    enum CodingKeys: String, CodingKey {
        case productID = "product_id"
        case isTrial  = "is_trial_period"
        case isIntro = "is_intro_offer"
        case price
        case state
        case paymentType = "payment_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.productID = try container.decode(String.self, forKey: .productID)
        self.isTrial = try container.decode(Bool.self, forKey: .isTrial)
        self.isIntro = try container.decodeIfPresent(Bool.self, forKey: .isIntro)
        self.price = try container.decodeIfPresent(Double.self, forKey: .price)
        self.state = try container.decode(SubscriptionAPIStatus.self, forKey: .state)
        self.paymentType = try container.decodeIfPresent(PaymentType.self, forKey: .paymentType) ?? .unknown
    }
}

public enum PaymentType: Codable {
    case lifetime
    case subscription
    case onetime
    case unknown
}
