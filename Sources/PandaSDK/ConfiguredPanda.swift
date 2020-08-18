//
//  ConfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 22.07.2020.
//

import Foundation
import UIKit

final public class Panda: PandaProtocol {

    internal static var notificationDispatcher: NotificationDispatcher!

    private struct Settings: Codable {
        var canceledScreenWasShown: Bool
        var billingScreenWasShown: Bool
        static let `default` = Settings(canceledScreenWasShown: false,
                                        billingScreenWasShown: false)
    }
    
    let networkClient: NetworkClient
    let cache: ScreenCache = ScreenCache()
    let user: PandaUser
    let appStoreClient: AppStoreClient
    private let settingsStorage: Storage<Settings> = CodableStorageFactory.userDefaults()
    private var viewControllers: Set<WeakObject<WebViewController>> = []

    public var onPurchase: ((String) -> Void)?
    public var onRestorePurchases: (([String]) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onDismiss: (() -> Void)?
    public var onSuccessfulPurchase: (() -> Void)?
    public let isConfigured: Bool = true


    init(user: PandaUser, networkClient: NetworkClient, appStoreClient: AppStoreClient) {
        self.user = user
        self.networkClient = networkClient
        self.appStoreClient = appStoreClient
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
    
    public func configure(apiKey: String, isDebug: Bool, callback: ((Bool) -> Void)?) {
        pandaLog("Already configured")
        callback?(true)
    }
    
    func onAppStoreClient(error: Error) {
        DispatchQueue.main.async {
            self.viewControllers.forEach { $0.value?.onFinishLoad() }
            self.onError?(error)
        }
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
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    self?.onError?(Errors.appStoreReceiptError(error))
                }
            case .success(let verification):
                print("productId = \(productId)\nid = \(verification.id)")
                DispatchQueue.main.async {
                    self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    self?.viewControllers.forEach({ $0.value?.dismiss(animated: true, completion: nil)})
                    self?.onPurchase?(productId)
                    self?.onSuccessfulPurchase?()
                }
            }
        }
    }
    
    func onAppStoreClientRestore(productIds: [String]) {
        DispatchQueue.main.async { [weak self] in
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
            self?.viewControllers.forEach({ $0.value?.dismiss(animated: true, completion: nil)})
            self?.onRestorePurchases?(productIds)
            self?.onSuccessfulPurchase?()
        }
    }
    
    public func registerDevice(token: Data) {
        networkClient.updateUser(pushToken: token.hexString(), user: user) { (result) in
            switch result {
            case .failure(let error):
                pandaLog("Register device error: \(error)")
            case .success:
                pandaLog("Device registred")
            }
        }
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
                callback?(.success(self.prepareViewController(screen: screen, screenType: .sales)))
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
                    callback?(.success(self.prepareViewController(screen: defaultScreen, screenType: .sales)))
                }
            case .success(let screen):
                self.cache[screenId] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen, screenType: .sales)))
                }
            }
        }
    }
    
    public func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?) {
        networkClient.getSubscriptionStatus(user: user) { (result) in
            switch result {
            case .failure(let error):
                statusCallback?(.failure(error))
            case .success(let apiResponse):
                let apiStatus = apiResponse.state
                let subscriptionStatus = SubscriptionStatus(with: apiStatus)
                statusCallback?(.success(subscriptionStatus))
            }
        }
    }

    public func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) {
        /// appid://panda/promo/product_id
        if url.host == "panda" {
            
            /// track analytics
            trackDeepLink(url.absoluteString)
            
            /// show screen
            if let product = url.pathComponents.last {
                showScreen(screenType: .product, product: product)
            } else {
                showScreen(screenType: .promo)
            }
        }
    }
    
    public func verifySubscriptions(callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        let receipt: String
        switch appStoreClient.receiptBase64String() {
            case .failure(let error):
                callback(.failure(Errors.appStoreReceiptError(error)))
                return
            case .success(let receiptString):
                receipt = receiptString
        }
        networkClient.verifySubscriptions(user: user, receipt: receipt) { (result) in
            callback(result)
        }
    }

    func addViewControllers(controllers: Set<WeakObject<WebViewController>>) {
        let updatedVCs = controllers.compactMap {$0.value}
        updatedVCs.forEach { (vc) in
            vc.viewModel = createViewModel(screenName: vc.viewModel?.screenName ?? "unknown")
        }
        viewControllers.formUnion(updatedVCs.map(WeakObject<WebViewController>.init(value:)))
    }
    
    private func prepareViewController(screen: ScreenData, screenType: ScreenType, product: String? = nil) -> WebViewController {
        let viewModel = createViewModel(screenName: screen.id, product: product)
        let controller = setupWebView(html: screen.html, viewModel: viewModel, screenType: screenType)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func createViewModel(screenName: String, product: String? = nil) -> WebViewModel {
        let viewModel = WebViewModel()
        viewModel.screenName = screenName
        if let product = product {
            viewModel.product = appStoreClient.products[product]
        }
        viewModel.onSurvey = { answer, screenId in
            pandaLog("AnswerSelected send: \(answer)")
            self.send(answer: answer, at: screenId)
        }
        viewModel.onFeedback = { feedback, screenId in
            pandaLog("Feedback send: \(String(describing: feedback))")
            if let text = feedback {
                self.send(feedback: text, at: screenId)
            }
        }
        viewModel.onPurchase = { [appStoreClient] productId, source, _ in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            appStoreClient.purchase(productId: productId)
        }
        viewModel.onRestorePurchase = { [appStoreClient] _ in
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
        return viewModel
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel, screenType: ScreenType) -> WebViewController {
        let controller = WebViewController()

        controller.view.backgroundColor = .init(red: 91/255, green: 191/255, blue: 186/244, alpha: 1)
        controller.modalPresentationStyle = screenType == .sales ? .overFullScreen : .pageSheet
        controller.viewModel = viewModel
        controller.loadPage(html: html)
        return controller
    }
    
    private func presentOnRoot(`with` viewController: UIViewController, _ completion: (() -> Void)? = nil) {
        if let root = UIApplication.getTopViewController() {
            root.modalPresentationStyle = .fullScreen
            root.present(viewController, animated: true, completion: completion)
        }
    }
    
    func onApplicationDidBecomeActive() {
        getSubscriptionStatus { [weak self, settingsStorage] (result) in
            let status: SubscriptionStatus
            switch result {
            case .failure(let error):
                pandaLog("SubscriptionStatus Error: \(error)")
                return
            case .success(let value):
                status = value
            }
            var settings = settingsStorage.fetch() ?? Settings.default
            switch status {
            case .canceled:
                settings.billingScreenWasShown = false
                settingsStorage.store(settings)
                guard settings.canceledScreenWasShown == false else { break }
                self?.showScreen(screenType: .survey, onShow: { [settingsStorage] result in
                    settings.canceledScreenWasShown = true
                    settingsStorage.store(settings)
                })
            case .billing:
                settings.canceledScreenWasShown = false
                settingsStorage.store(settings)
                guard settings.billingScreenWasShown == false else { break }
                self?.showScreen(screenType: .billing, onShow: { [settingsStorage] result in
                    settings.billingScreenWasShown = true
                    settingsStorage.store(settings)
                })
            default:
                settings.canceledScreenWasShown = false
                settings.billingScreenWasShown = false
                settingsStorage.store(settings)
            }
        }
    }
    
    public func showScreen(screenType: ScreenType, product: String? = nil, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        networkClient.loadScreen(user: user, screenId: nil, screenType: screenType) { (screenResult) in
            switch screenResult {
            case .failure(let error):
                pandaLog("ShowScreen Error: \(error)")
                onShow?(.failure(error))
            case .success(let screenData):
                DispatchQueue.main.async {
                    self.presentOnRoot(with: self.prepareViewController(screen: screenData, screenType: screenType, product: product)) {
                        onShow?(.success(true))
                    }
                }
            }
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool {
        guard SubscriptionStatus.pandaEvent(from: notification) != nil else {
            return false
        }
        completionHandler([.alert])
        return true
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool {
        guard let status = SubscriptionStatus.pandaEvent(from: response.notification) else {
            return false
        }
        switch status {
        case .canceled:
            if UIApplication.shared.applicationState == .active {
                showScreen(screenType: .survey)
            }
        default: break
        }
        completionHandler()
        return true
    }

}

extension Panda {
    fileprivate func send(feedback text: String, at screenId: String?) {
        networkClient.sendFeedback(user: user, screenId: screenId ?? "default", feedback: text) { result in
            switch result {
            case .failure(let error):
                pandaLog("Send Feedback \(text) text failed: \(error)!")
            case .success(let id):
                pandaLog("Send Feedback \(id)")
            }
        }
    }
    
    fileprivate func send(answer text: String, at screenId: String?) {
        networkClient.sendAnswers(user: user, screenId: screenId ?? "default", answer: text) { result in
            switch result {
            case .failure(let error):
                pandaLog("Send Answers \(text) text failed: \(error)!")
            case .success(let id):
                pandaLog("Send Answers \(id)")
            }
        }
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
    
    func trackDeepLink(_ link: String) {
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
        onSuccessfulPurchase = other.onSuccessfulPurchase
    }
}
