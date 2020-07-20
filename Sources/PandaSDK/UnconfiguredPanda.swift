//
//  UnconfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 20.07.2020.
//

import Foundation

final class UnconfiguredPanda: PandaProtocol {
    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?) {
        
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        callback?(.failure(Errors.notConfigured))
    }
    func prefetchScreen(screenId: String?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
    }
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?,
                               screenCallback: ((Result<UIViewController, Error>) -> Void)?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        statusCallback?(.failure(Errors.notConfigured))
    }

    var onPurchase: ((String) -> Void)?
    var onRestorePurchases: (([String]) -> Void)?
    var onError: ((Error) -> Void)?
    var onDismiss: (() -> Void)?
}

