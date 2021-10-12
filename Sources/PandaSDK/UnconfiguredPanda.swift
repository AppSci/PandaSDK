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
    var pandaUserId: String?
    var pandaCustomUserId: String?
    
    var viewControllers: Set<WeakObject<WebViewController>> = []
    var deviceToken: Data?
    var customUserId: String?
    var appsFlyerId: String?
    var advertisementId: String?
    var facebookIds: FacebookIds?
    var capiConfig: CAPIConfig?
    
    private static let configError = "Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\") and wait, until you get `callback(true)`"

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
    
    func registerAppsFlyer(id: String) {
        appsFlyerId = id
    }
    
    func registerIDFA(id: String) {
        advertisementId = id
    }
    
    func prefetchScreen(screenId: String?, payload: [String:Any]?) {
        pandaLog(UnconfiguredPanda.configError)
    }

    public func showScreen(screenType: ScreenType, screenId: String? = nil, product: String? = nil, autoDismiss: Bool = true, presentationStyle: UIModalPresentationStyle = .pageSheet, payload: [String: Any]? = nil, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        pandaLog(UnconfiguredPanda.configError)
        onShow?(.failure(Errors.notConfigured))
    }
    
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?) {
        pandaLog(UnconfiguredPanda.configError)
        statusCallback?(.failure(Errors.notConfigured))
    }

    func getScreen(screenId: String?, payload: [String: Any]? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        getScreen(screenType: .sales, screenId: screenId, payload: payload, callback: callback)
    }
    
    func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, product: String? = nil, payload: [String: Any]? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        let shouldShowDefaultScreenOnFailure = (payload?["no_default"] as? Bool) != true
        guard shouldShowDefaultScreenOnFailure else {
            DispatchQueue.main.async {
                callback?(.failure(Errors.notConfigured))
            }
            return
        }
        guard let screenData = ScreenData.default else {
            DispatchQueue.main.async {
                callback?(.failure(Errors.message("Cannot find default screen html")))
            }
            return
        }

        DispatchQueue.main.async {
            callback?(.success(self.prepareViewController(screenData: screenData, screenType: screenType, product: product, payload: payload)))
        }
    }
    
    func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) {
        pandaLog(UnconfiguredPanda.configError)
    }
    
    private func prepareViewController(screenData: ScreenData, screenType: ScreenType, product: String? = nil, payload: [String: Any]? = nil) -> WebViewController {
        let viewModel = createViewModel(screenData: screenData, product: product, payload: payload)
        let controller = setupWebView(html: screenData.html, viewModel: viewModel)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func createViewModel(screenData: ScreenData, product: String? = nil, payload: [String: Any]? = nil) -> WebViewModel {
        let viewModel = WebViewModel(screenData: screenData, payload: payload)
        let extraValues = viewModel.payload?["extra_event_values"] as? [String: String]
        let source = extraValues?["entry_point"]
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
        viewModel.onRestorePurchase = { [weak self] view, screenId, screenName in
            pandaLog("Restore")
            self?.reconfigure(callback: { (result) in
                switch result {
                case .success:
                    pandaLog("Reconfigured")
                    view.viewModel?.onRestorePurchase?(view, screenId, screenName)
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
        viewModel.onSubscriptionTerms = openSubscriptionTerms
        viewModel.onBillingIssue = { view in
            pandaLog("onBillingIssue")
            self.openBillingIssue()
            view.dismiss(animated: true, completion: nil)
        }
        viewModel.dismiss = { [weak self] status, view, screenId, screenName in
            pandaLog("Dismiss")
            if let screenID = screenId, let name = screenName {
                self?.trackClickDismiss(screenId: screenID, screenName: name, source: source)
            }
            view.dismiss(animated: true, completion: nil)
            self?.onDismiss?()
        }
        viewModel.onViewWillAppear = { [weak self] screenId, screenName in
            guard let screenId = screenId, let screenName = screenName else { return }
            self?.send(event: .screenWillShow(screenId: screenId, screenName: screenName, source: source))
        }
        viewModel.onViewDidAppear = { [weak self] screenId, screenName in
            guard let screenId = screenId, let screenName = screenName else { return }
            self?.send(event: .screenShowed(screenId: screenId, screenName: screenName, source: source))
        }
        viewModel.onCustomEvent = { [weak self] eventName, eventParameters in
            self?.send(event: .customEvent(name: eventName, parameters: eventParameters))
        }
        return viewModel
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel) -> WebViewController {
        let controller = WebViewController()

        controller.view.backgroundColor = viewModel.payload?["background"] as? UIColor
        controller.modalPresentationStyle = .overFullScreen
        controller.viewModel = viewModel
        controller.loadPage(html: html)
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
        pandaLog(UnconfiguredPanda.configError)
        callback(.failure(Errors.notConfigured))
    }
    
    func purchase(productID: String) {
        pandaLog(UnconfiguredPanda.configError)
    }
    
    func restorePurchase() {
        pandaLog(UnconfiguredPanda.configError)
    }
    
    func setCustomUserId(id: String) {
        self.customUserId = id
    }
    
    public func setFBIds(facebookIds: FacebookIds) {
        self.facebookIds = facebookIds
    }
    
    func resetIDFVAndIDFA() {
        self.advertisementId = ""
    }
    
    func register(facebookLoginId: String?, email: String?, firstName: String?, lastName: String?, username: String?, phone: String?, gender: Int?) {
        self.capiConfig = .init(email: email,
                                facebookLoginId: facebookLoginId,
                                firstName: firstName,
                                lastName: lastName,
                                username: username,
                                phone: phone,
                                gender: gender)
    }
}

