//
//  PurchaseResult.swift
//  
//
//  Created by Denys Danyliuk on 13.09.2023.
//

import StoreKit

public enum PurchaseResult {
    case success(Transaction, Product)
    case cancelled
    case pending
}
