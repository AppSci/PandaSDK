//
//  PandaAnalytics.swift
//  NVActivityIndicatorView
//
//  Created by Kuts on 09.09.2020.
//

import Foundation
public enum PandaEvent {
    case subscriptionSelect(screenId: String, screenName: String, productId: String)
    case purchaseStarted(screenId: String, screenName: String, productId: String, source: String?)
    case successfulPurchase(screenId: String, screenName: String, productId: String, source: String?, course: String?)
    case purchaseError(error: Error, source: String?)
    case onApplePaySuccessfulPurchase(productID: String?, screenID: String)
    case onStartApplePayProcess 
    case screenDismissed(screenId: String, screenName: String, source: String?)
    case surveyAnswerSelect(screenId: String, screenName: String, answerId: String)
    case surveyPosted(screenId: String, screenName: String, feedbackId: String)
    case screenShowed(screenId: String, screenName: String, source: String?, course: String?)
    case screenLoaded(screenId: String, screenName: String, source: String?)
    case screenWillShow(screenId: String, screenName: String, source: String?)
    case screenShowFailed(screenId: String, screenType: String?)
    case trackOpenLink(link: String, result: String)
    case trackDeepLink(link: String)
    case privacyPolicyTap
    case termsAndConditionsTap
    case billingDetailsTap
    case subscriptionTermsTap
    case customEvent(name: String, parameters: [String: String])
    case onPandaWillVerify(screenId: String, screenName: String, productId: String)
    case onSupportUkraineAnyButtonTap
    case onDontHaveApplePay(screenId: String, source: String?, destination: String?)
    case onTutorsHowOfferWorks(screenId: String, source: String?, destination: String?)
}

public protocol PandaAnalyticsObserver: AnyObject {
    func handle(event: PandaEvent)
}

protocol ObserverSupport: AnyObject {
    var observers: [ObjectIdentifier: WeakObserver] {get set}
}

extension ObserverSupport {
    func send(event: PandaEvent) {
        var empty = 0
        observers.forEach {
            $0.value.handle(event: event)
            if $0.value.isValid { empty += 1 }
        }
        //clean if more than 50% are deleted
        if observers.count > 256 && empty > observers.count/2 {
            observers = observers.filter { $0.value.value != nil }
        }
    }
}

class WeakObserver: PandaAnalyticsObserver {
    
    private(set) weak var value: PandaAnalyticsObserver?
    init(value: PandaAnalyticsObserver) {
        self.value = value
    }
    
    var isValid: Bool {
        return value != nil
    }

    func handle(event: PandaEvent) {
        value?.handle(event: event)
    }
}
