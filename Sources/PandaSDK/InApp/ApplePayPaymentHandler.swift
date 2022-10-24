//
//  ApplePayPaymentHandler.swift
//  
//
//  Created by Roman Mishchenko on 02.06.2022.
//

import Foundation
import PassKit
import Combine

public enum ApplePayPaymentHandlerOutputMessage {
    case failedToPresentPayment
    case paymentFinished(_ status: PKPaymentAuthorizationStatus, _ billingID: String, _ paymentData: Data, _ productID: String)
}

final class ApplePayPaymentHandler: NSObject {

    private var paymentController: PKPaymentAuthorizationController?
    private var paymentSummaryItems = [PKPaymentSummaryItem]()
    private var paymentStatus = PKPaymentAuthorizationStatus.failure
    private var billingID: String? = nil
    private var productID: String? = nil
    private var paymentData: Data? = nil
    private let configuration: ApplePayConfiguration
    
    let outputPublisher: AnyPublisher<ApplePayPaymentHandlerOutputMessage, Error>
    private let outputSubject = PassthroughSubject<ApplePayPaymentHandlerOutputMessage, Error>()
    
    init(configuration: ApplePayConfiguration) {
        self.configuration = configuration
        self.outputPublisher = outputSubject.eraseToAnyPublisher()
    }
    
    static let supportedNetworks: [PKPaymentNetwork] = [
        .amex,
        .masterCard,
        .visa,
        .discover
    ]

    class func applePayStatus() -> (canMakePayments: Bool, canSetupCards: Bool) {
        return (PKPaymentAuthorizationController.canMakePayments(),
                PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks))
    }

    func startPayment(
        with label: String,
        price: String?,
        currency: String?,
        billingID: String?,
        countryCode: String?,
        productID: String?
    ) {
        guard
            let price = price,
            let currency = currency,
            let billingID = billingID,
            let countryCode = countryCode
        else {
            self.outputSubject.send(.failedToPresentPayment)
            return
        }

        let product = PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(string: price), type: .pending)
        let finalProduct = PKPaymentSummaryItem(label: "GM APPDEV LIMITED", amount: NSDecimalNumber(string: price), type: .final)

        paymentSummaryItems = [product, finalProduct]

        // Create a payment request.
        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = paymentSummaryItems
        paymentRequest.merchantIdentifier = configuration.merchantIdentifier
        paymentRequest.merchantCapabilities = .capability3DS
        
        paymentRequest.countryCode = countryCode
        paymentRequest.currencyCode = currency
        paymentRequest.supportedNetworks = ApplePayPaymentHandler.supportedNetworks

        // Display the payment request.
        paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController?.delegate = self
        
        paymentController?.present(completion: { presented in
            if !presented {
                self.outputSubject.send(.failedToPresentPayment)
            } else {
                self.billingID = billingID
                self.productID = productID
            }
        })
    }
}

extension ApplePayPaymentHandler: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        paymentStatus = .success
        paymentData = payment.token.paymentData
        completion(PKPaymentAuthorizationResult(status: .success, errors: []))
    }
    
    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss {
            // The payment sheet doesn't automatically dismiss once it has finished. Dismiss the payment sheet.
            DispatchQueue.main.async {
                guard
                    let paymentData = self.paymentData,
                    let billingID = self.billingID,
                    let productID = self.productID
                else {
                    return
                }
                self.outputSubject.send(.paymentFinished(self.paymentStatus, billingID, paymentData, productID))
            }
        }
    }
}
