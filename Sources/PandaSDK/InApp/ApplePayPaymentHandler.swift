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
    case paymentFinished(_ status: PKPaymentAuthorizationStatus, _ productId: String, _ paymentData: Data)
}

final class ApplePayPaymentHandler: NSObject {

    private var paymentController: PKPaymentAuthorizationController?
    private var paymentSummaryItems = [PKPaymentSummaryItem]()
    private var paymentStatus = PKPaymentAuthorizationStatus.failure
    private var productId: String? = nil
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
    
    func startPayment(with label: String, price: String, currency: String, productId: String) {
        let product = PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(string: price), type: .final)
        paymentSummaryItems = [product]
        
        // Create a payment request.
        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = paymentSummaryItems
        paymentRequest.merchantIdentifier = configuration.merchantIdentifier
        paymentRequest.merchantCapabilities = .capability3DS
        
        paymentRequest.countryCode = configuration.countryCode
        paymentRequest.currencyCode = currency
        paymentRequest.supportedNetworks = ApplePayPaymentHandler.supportedNetworks

        // Display the payment request.
        paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController?.delegate = self
        
        paymentController?.present(completion: { presented in
            if !presented {
                self.outputSubject.send(.failedToPresentPayment)
            } else {
                self.productId = productId
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
                    let productId = self.productId
                else {
                    return
                }
                self.outputSubject.send(.paymentFinished(self.paymentStatus, productId, paymentData))
            }
        }
    }
}
