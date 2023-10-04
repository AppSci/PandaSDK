//
//  VerificationClient.swift
//  
//
//  Created by Denys Danyliuk on 30.08.2023.
//

import Foundation

protocol VerificationClient {
    /// In-app
    func verifySubscriptions(
        user: PandaUser,
        receipt: String,
        source: PaymentSource?,
        retries: Int,
        callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void
    )
    
    /// Apple Pay
    func verifyApplePayRequest(
        user: PandaUser,
        paymentData: Data,
        billingID: String,
        webAppId: String,
        callback: @escaping (Result<ApplePayResult, Error>) -> Void
    )
}

extension VerificationClient {
    func verifySubscriptions(
        user: PandaUser,
        receipt: String,
        source: PaymentSource?,
        retries: Int
    ) async throws -> ReceiptVerificationResult {
        try await withCheckedThrowingContinuation { continuation in
            verifySubscriptions(
                user: user,
                receipt: receipt,
                source: source,
                retries: retries
            ) { result in
                continuation.resume(with: result)
            }
        }
    }
}
