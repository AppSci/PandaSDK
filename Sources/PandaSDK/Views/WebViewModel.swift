//
//  WebViewModel.swift
//  Panda
//
//  Created by Kuts on 01.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import StoreKit

protocol WebViewModelProtocol {
    var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ sceenId: String) -> Void)!  { get set }
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)? { get set }
    var onRestorePurchase: ((_ viewController: WebViewController) -> Void)? { get set }
    var onTerms: (() -> Void)? { get set }
    var onPolicy: (() -> Void)? { get set }
    var onSurvey: ((_ answer: String, _ sceenId: String?) -> Void)? { get set }
    var onFeedback: ((_ feedback: String?, _ sceenId: String?) -> Void)? { get set }
    var dismiss: ((_ success: Bool, _ viewController: WebViewController) -> Void)? { get set }
}

class WebViewModel: WebViewModelProtocol {
    
    @objc var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ sceenId: String) -> Void)!
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)?
    var onRestorePurchase: ((_ viewController: WebViewController) -> Void)?
    var onTerms: (() -> Void)?
    var onPolicy: (() -> Void)?
    var onSurvey: ((_ answer: String, _ sceenId: String?) -> Void)?
    var onFeedback: ((_ feedback: String?, _ sceenId: String?) -> Void)?
    var dismiss: ((_ success: Bool, _ viewController: WebViewController) -> Void)?
    
    let screenId: String
    var product: SKProduct?
    
    
    init(screenId: String) {
        self.screenId = screenId
        setupObserver()
    }
    
    func setupObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(getter: onPurchase),
                                               name: NSNotification.Name(rawValue: "SubscriptionBooster.onPurchase"),
                                               object: nil)
    }
}
