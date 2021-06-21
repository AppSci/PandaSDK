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
    var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ screenId: String, _ screenName: String) -> Void)!  { get set }
    var onViewWillAppear: ((_ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onViewDidAppear: ((_ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onDidFinishLoading: ((_ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)? { get set }
    var onRestorePurchase: ((_ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onTerms: (() -> Void)? { get set }
    var onPolicy: (() -> Void)? { get set }
    var onSubscriptionTerms: (() -> Void)? { get set }
    var onSurvey: ((_ answer: String, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onFeedback: ((_ feedback: String?, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
    var onCustomEvent: ((_ name: String, _ parameters: [String: String]) -> Void)? { get set }
    var dismiss: ((_ success: Bool, _ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)? { get set }
}

class WebViewModel: WebViewModelProtocol {
    
    @objc var onPurchase: ((_ product: String?, _ source: String, _ viewController: WebViewController, _ sceenId: String, _ screenName: String) -> Void)!
    var onViewWillAppear: ((_ screenId: String?, _ screenName: String?) -> Void)?
    var onViewDidAppear: ((_ screenId: String?, _ screenName: String?) -> Void)?
    var onDidFinishLoading: ((_ screenId: String?, _ screenName: String?) -> Void)?
    var onBillingIssue: ((_ viewController: WebViewController) -> Void)?
    var onRestorePurchase: ((_ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)?
    var onTerms: (() -> Void)?
    var onPolicy: (() -> Void)?
    var onSubscriptionTerms: (() -> Void)?
    var onSurvey: ((_ answer: String, _ screenId: String?, _ screenName: String?) -> Void)?
    var onFeedback: ((_ feedback: String?, _ screenId: String?, _ screenName: String?) -> Void)?
    var onCustomEvent: ((_ name: String, _ parameters: [String: String]) -> Void)?
    var dismiss: ((_ success: Bool, _ viewController: WebViewController, _ screenId: String?, _ screenName: String?) -> Void)?
    
    let screenData: ScreenData
    var product: SKProduct?
    let payload: [String: Any]?
    
    init(screenData: ScreenData, payload: [String: Any]? = nil) {
        self.screenData = screenData
        self.payload = payload
        setupObserver()
    }
    
    func setupObserver() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(getter: onPurchase),
                                               name: NSNotification.Name(rawValue: "SubscriptionBooster.onPurchase"),
                                               object: nil)
    }
}
