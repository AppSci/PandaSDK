//
//  Panda.swift
//  Panda
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit

public protocol PandaProtocol: class {
    
    /**
     Returns screen from Panda Web
     - parameter screenId: Optional. ID screen. If `nil` - returns default screen from Panda Web
     - parameter callback: Optional. Returns Result for getting screen
     */
    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?)
    
    /**
     Prefetches screen from Panda Web - if you want to cashe Screen before displaying it
     - parameter screenId: Optional. ID screen. If `nil` - returns default screen from Panda Web
     */
    func prefetchScreen(screenId: String?)
    
    // MARK: - Handle Purchases
    /**
     Purchase product callback.
     Callback for successful purchase in Panda purchase screen - you can validate & do you own setup in this callback
     - parameter String in callback: Product ID that was purchased.
     */
     var onPurchase: ((String) -> Void)? { get set }
    
    /**
     Restore purchase callback
     Callback for successful restore in Panda purchase screen.
     - parameter String in callback: Product ID that was restored.
     */
    var onRestorePurchases: (([String]) -> Void)? { get set }
    
    /**
     Called when purchase failed in Panda purchase screen.
    */
    var onError: ((Error) -> Void)? { get set }
    
    /**
     Called when user click on Close cross in Panda purchase screen.
    */
    var onDismiss: (() -> Void)? { get set }

    /**
     You can call to check subscription status of User
    */
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?,
                               screenCallback: ((Result<UIViewController, Error>) -> Void)?)
}

public extension Panda {
    
    /**
     Initializes PandaSDK. You should call it in `func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool`. All Panda funcs must be  called after Panda is configured
     
     - parameter apiKey: Required. Your api key.
     - parameter isDebug: Optional. Please, use `true` for debugging, `false` for production. Default is `true`.
     - parameter callback: Optional. You can do check if Panda SDK in configured.
     */
    static func configure(token: String, isDebug: Bool = true, callback: ((Bool) -> Void)?) {
        guard let unconfigured = shared as? UnconfiguredPanda else {
            pandaLog("Already configured")
            callback?(true)
            return
        }
        unconfigured.configure(token: token, isDebug: isDebug) { (result) in
            switch result {
            case .success(let panda):
                shared = panda
                callback?(true)
            case .failure:
                callback?(false)
            }
        }
    }
}

final public class Panda: PandaProtocol {

    public private(set) static var shared: PandaProtocol = UnconfiguredPanda()
    
    let networkClient: NetworkClient
    let cache: ScreenCache = ScreenCache()
    let user: PandaUser
    let appStoreClient: AppStoreClient
    var viewControllers: Set<WeakObject<WebViewController>> = []

    public var onPurchase: ((String) -> Void)?
    public var onRestorePurchases: (([String]) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onDismiss: (() -> Void)?
    
    init(user: PandaUser, networkClient: NetworkClient, appStoreClient: AppStoreClient, copyCallbacks other: PandaProtocol? = nil) {
        self.user = user
        self.networkClient = networkClient
        self.appStoreClient = appStoreClient
        other.map(self.copyCallbacks(from:))
        configureAppStoreClient()
    }
    
    internal func configureAppStoreClient() {
        appStoreClient.onError = { [weak self] error in
            self?.onAppStoreClient(error: error)
        }
        appStoreClient.onPurchase = { [weak self] productId in
            self?.onAppStoreClientPurchase(productId: productId)
        }
        appStoreClient.onRestore = { [weak self] productIds in
            self?.onAppStoreClientRestore(productIds: productIds)
        }
        appStoreClient.startObserving()
    }
    
    func onAppStoreClient(error: Error) {
        onError?(error)
        viewControllers.forEach { $0.value?.onFinishLoad() }
    }
    
    func onAppStoreClientPurchase(productId: String) {
        let receipt: String
        switch appStoreClient.receiptBase64String() {
            case .failure(let error):
                onError?(Errors.appStoreReceiptError(error))
                return
            case .success(let receiptString):
                receipt = receiptString
        }
        networkClient.verifySubscriptions(user: user, receipt: receipt) { [weak self] (result) in
            defer {
                self?.viewControllers.forEach { $0.value?.onFinishLoad() }
            }
            switch result {
            case .failure(let error):
                self?.onError?(Errors.appStoreReceiptError(error))
            case .success(let verification):
                print("productId = \(productId)\nid = \(verification.id)")
                self?.onPurchase?(verification.id)
            }
        }
    }
    
    func onAppStoreClientRestore(productIds: [String]) {
        onRestorePurchases?(productIds)
        viewControllers.forEach { $0.value?.onFinishLoad() }
    }
    
    public func prefetchScreen(screenId: String?) {
        networkClient.loadScreen(user: user, screenId: screenId) { [weak self] result in
            guard let self = self else {
                pandaLog("Panda is missing!")
                return
            }
            switch result {
            case .failure(let error):
                pandaLog("Prefetch \(screenId ?? "default") screen failed: \(error)!")
            case .success(let screen):
                self.cache[screenId] = screen
                pandaLog("Prefetched \(screenId ?? "default")")
            }
        }
    }
    
    public func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?) {
        if let screen = cache[screenId] {
            DispatchQueue.main.async {
                callback?(.success(self.prepareViewController(screen: screen)))
            }
            return
        }
        networkClient.loadScreen(user: user, screenId: screenId) { [weak self] result in
            guard let self = self else {
                callback?(.failure(Errors.message("Panda is missing!")))
                return
            }
            switch result {
            case .failure(let error):
                guard let defaultScreen = try? NetworkClient.loadScreenFromBundle() else {
                    callback?(.failure(error))
                    return
                }
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: defaultScreen)))
                }
            case .success(let screen):
                self.cache[screenId] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen)))
                }
            }
        }
    }
    
    public func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?,
                                      screenCallback: ((Result<UIViewController, Error>) -> Void)?) {
        networkClient.getSubscriptionStatus(user: user) { [weak self] (result) in
            guard let self = self else {
                statusCallback?(.failure(Errors.message("Panda is missing!")))
                return
            }
            switch result {
            case .failure(let error):
                statusCallback?(.failure(error))
            case .success(let apiResponse):
                let apiStatus = apiResponse.state
                let subscriptionStatus = SubscriptionStatus(with: apiStatus)
                statusCallback?(.success(subscriptionStatus))
                switch subscriptionStatus {
                case .canceled:
                    self.networkClient.loadScreen(user: self.user, screenId: nil, screenType: .survey) { (screenResult) in
                        switch screenResult {
                        case.failure(let error):
                            screenCallback?(.failure(error))
                        case .success(let screenData):
                            DispatchQueue.main.async {
                                screenCallback?(.success(self.prepareViewController(screen: screenData)))
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
    }
    
    private func prepareViewController(screen: ScreenData) -> WebViewController {
        let viewModel = WebViewModel()
        viewModel.screenName = screen.id
        viewModel.onSurvey = { value in
            pandaLog("Survey: \(value)")
        }
        viewModel.onPurchase = { [appStoreClient] productId, source in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            appStoreClient.purchase(productId: productId)
        }
        viewModel.onRestorePurchase = { [appStoreClient] in
            pandaLog("Restore")
            appStoreClient.restore()
        }
        
        viewModel.onTerms = openTerms
        viewModel.onPolicy = openPolicy
        viewModel.onBillingIssue = { view in
            pandaLog("onBillingIssue")
            self.openBillingIssue()
            view.dismiss(animated: true, completion: nil)
        }
        viewModel.dismiss = { [weak self] status, view in
            pandaLog("Dismiss")
            self?.trackClickDismiss()
            view.dismiss(animated: true, completion: nil)
            self?.onDismiss?()
        }
        let controller = setupWebView(html: screen.html, viewModel: viewModel)
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

}


extension PandaProtocol {
    func openBillingIssue() {
        openLink(link: ClientConfig.current.billingUrl) { result in
            self.trackOpenLink("billing_issue", result)
        }
    }
    
    func openTerms() {
        openLink(link: ClientConfig.current.termsUrl) { result in
            self.trackOpenLink("terms", result)
        }
    }
    
    func openPolicy() {
        openLink(link: ClientConfig.current.policyUrl) { result in
            self.trackOpenLink("policy", result)
        }
    }
    
    func openLink(link: String, completionHandler completion: ((Bool) -> Void)? = nil) {
        if let url = URL(string: link), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }

    func trackOpenLink(_ link: String, _ result: Bool) {
    }
    
    func trackClickDismiss() {
    }
}

class ScreenCache {
    var cache: [String: ScreenData] = [:]
    let nilKey = "<nil>"
    
    subscript(screenId: String?) -> ScreenData? {
        get {
            return cache[screenId ?? nilKey]
        }
        set(newValue) {
            guard let newValue = newValue else {
                cache.removeValue(forKey: screenId ?? nilKey)
                return
            }
            cache[screenId ?? nilKey] = newValue
        }
    }
    
}

extension PandaProtocol {
    func copyCallbacks(from other: PandaProtocol) {
        onPurchase = other.onPurchase
        onRestorePurchases = other.onRestorePurchases
        onError = other.onError
        onDismiss = other.onDismiss
    }
}
