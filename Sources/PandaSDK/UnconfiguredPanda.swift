//
//  UnconfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 20.07.2020.
//

import Foundation
import UIKit

final class UnconfiguredPanda: PandaProtocol, ObserverSupport {
    
    var onPurchase: ((String) -> Void)?
    var onRestorePurchases: (([String]) -> Void)?
    var onError: ((Error) -> Void)?
    var onDismiss: (() -> Void)?
    var onSuccessfulPurchase: (() -> Void)?
    let isConfigured: Bool = false
    var pandaUserId: String?  = nil
    
    var viewControllers: Set<WeakObject<WebViewController>> = []
    var deviceToken: Data?
    var customUserId: String?
    
    struct LastConfigurationAttempt {
        var apiKey: String
        var isDebug: Bool
    }
    private var lastConfigurationAttempt: LastConfigurationAttempt?

    var observers: [ObjectIdentifier: WeakObserver] = [:]
    func add(observer: PandaAnalyticsObserver) {
        observers[ObjectIdentifier(observer)] = WeakObserver(value: observer)
    }
    
    func remove(observer: PandaAnalyticsObserver) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
    }

    func configure(apiKey: String, isDebug: Bool = true, callback: ((Bool) -> Void)?) {
        lastConfigurationAttempt = LastConfigurationAttempt(apiKey: apiKey, isDebug: isDebug)
        Panda.configure(apiKey: apiKey, isDebug: isDebug, unconfigured: self, callback: { result in
            switch result {
            case .failure:
                callback?(false)
            case .success:
                callback?(true)
            }
        })
    }
    
    private func reconfigure(callback: @escaping (Result<Panda, Error>) -> Void) {
        guard let configAttempt = lastConfigurationAttempt else {
            viewControllers.forEach { $0.value?.onFinishLoad() }
            callback(.failure(Errors.notConfigured))
            return
        }
        Panda.configure(apiKey: configAttempt.apiKey, isDebug: configAttempt.isDebug, unconfigured: self) { [viewControllers] (result) in
            if case .failure = result {
                viewControllers.forEach { $0.value?.onFinishLoad() }
            }
            callback(result)
        }
    }

    func registerDevice(token: Data) {
        deviceToken = token
    }
    
    func prefetchScreen(screenId: String?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
    }

    public func showScreen(screenType: ScreenType, screenId: String? = nil, product: String? = nil, autoDismiss: Bool = true, presentationStyle: UIModalPresentationStyle = .pageSheet, payload: [String: Any]? = nil, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        onShow?(.failure(Errors.notConfigured))
    }
    
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        statusCallback?(.failure(Errors.notConfigured))
    }

    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?) {
        getScreen(callback: callback)
    }
    
    func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, product: String? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        let defaultScreen: ScreenData
        do {
            defaultScreen = try NetworkClient.loadScreenFromBundle()
        } catch {
            DispatchQueue.main.async {
                callback?(.failure(error))
            }
            return
        }
        DispatchQueue.main.async {
            callback?(.success(self.prepareViewController(screenData: defaultScreen)))
        }
    }
    
    func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
    }
    
    private func prepareViewController(screenData: ScreenData) -> WebViewController {
        let viewModel = WebViewModel(screenData: screenData)
        viewModel.onSurvey = { value, screenId, screenName in
            pandaLog("Survey: \(value)")
        }
        viewModel.onPurchase = { [weak self] productId, source, view, screenId, screenName in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            self?.reconfigure(callback: { (result) in
                switch result {
                case .success:
                    pandaLog("Reconfigured")
                    view.viewModel?.onPurchase?(productId, source, view, screenId, screenName)
                case .failure(let error):
                    pandaLog("Reconfigured error: \(error)")
                    DispatchQueue.main.async {
                        view.showInternetConnectionAlert()
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                        self?.onError?(error)
                    }
                }
            })
        }
        viewModel.onRestorePurchase = { [weak self] view in
            pandaLog("Restore")
            self?.reconfigure(callback: { (result) in
                switch result {
                case .success:
                    pandaLog("Reconfigured")
                    view.viewModel?.onRestorePurchase?(view)
                case .failure(let error):
                    pandaLog("Reconfigured error: \(error)")
                    DispatchQueue.main.async {
                        view.showInternetConnectionAlert()
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                        self?.onError?(error)
                    }
                }
            })
        }
        viewModel.onTerms = openTerms
        viewModel.onPolicy = openPolicy
        viewModel.onBillingIssue = { view in
            pandaLog("onBillingIssue")
            self.openBillingIssue()
            view.dismiss(animated: true, completion: nil)
        }
        viewModel.dismiss = { [weak self] status, view, screenId, screenName in
            pandaLog("Dismiss")
            if let screenID = screenId, let name = screenName {
                self?.trackClickDismiss(screenId: screenID, screenName: name)
            }
            view.dismiss(animated: true, completion: nil)
            self?.onDismiss?()
        }
        viewModel.onViewWillAppear = { [weak self] screenId, screenName in
            guard let screenId = screenId, let screenName = screenName else { return }
            self?.send(event: .screenWillShow(screenId: screenId, screenName: screenName))
        }
        viewModel.onViewDidAppear = { [weak self] screenId, screenName in
            guard let screenId = screenId, let screenName = screenName else { return }
            self?.send(event: .screenShowed(screenId: screenId, screenName: screenName))
        }
        let controller = setupWebView(html: screenData.html, viewModel: viewModel)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel) -> WebViewController {
        let controller = WebViewController()

        controller.view.backgroundColor = .init(red: 91/255, green: 191/255, blue: 186/244, alpha: 1)
        controller.modalPresentationStyle = .overFullScreen
        controller.loadPage(html: html)
        controller.viewModel = viewModel
        return controller
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {
        guard SubscriptionStatus.pandaEvent(from: notification) != nil else {
            return false
        }
        completionHandler([.alert])
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        guard SubscriptionStatus.pandaEvent(from: response.notification) != nil else {
            return false
        }
        completionHandler()
        return true
    }

    public func verifySubscriptions(callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        callback(.failure(Errors.notConfigured))
    }
    
    func setCustomUserId(id: String) {
        self.customUserId = id
    }
}

