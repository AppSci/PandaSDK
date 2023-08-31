//
//  ApplePayResult.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation

public struct ApplePayResult: Codable {
    let transactionID: String
    let transactionStatus: TransactionSolidStatus?

    enum CodingKeys: String, CodingKey {
        case transactionID = "TransactionID"
        case transactionStatus = "transaction_status"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.transactionID = try container.decode(String.self, forKey: .transactionID)
        self.transactionStatus = try container.decode(TransactionSolidStatus.self, forKey: .transactionStatus)
    }
}
