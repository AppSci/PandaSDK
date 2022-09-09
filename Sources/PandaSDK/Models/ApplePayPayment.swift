//
//  ApplePayPayment.swift
//  
//
//  Created by Roman Mishchenko on 02.06.2022.
//

import Foundation

struct ApplePayPaymentInfo: Codable {
    let header: PaymnetHeader
    let data: String
    let signature: String
    let version: String
}

struct PaymnetHeader: Codable {
    let ephemeralPublicKey: String
    let publicKeyHash: String
    let transactionId: String
}

struct ApplePayPayment: Codable {
    let data: String
    let ephemeralPublicKey: String
    let publicKeyHash: String
    let transactionId: String
    let signature: String
    let version: String
    let sandbox: Bool
    let webAppId: String
    let productId: String
    let userId: String
    
    enum CodingKeys: String, CodingKey {
        case data
        case ephemeralPublicKey = "ephemeral_public_key"
        case publicKeyHash = "public_key_hash"
        case transactionId = "transaction_id"
        case signature
        case version
        case sandbox
        case webAppId = "web_app_id"
        case productId = "product_id"
        case userId = "user_id"
    }
}
