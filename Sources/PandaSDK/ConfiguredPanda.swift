//
//  ConfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 22.07.2020.
//

import Foundation
import UIKit

final public class Panda: PandaProtocol, ObserverSupport {

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
        appStoreClient.onPurchase = { [weak self] productId, source in
            self?.onAppStoreClientPurchase(productId: productId, source: source)
        }
        appStoreClient.onRestore = { [weak self] productIds in
            self?.onAppStoreClientRestore(productIds: productIds)
        }
        appStoreClient.startObserving()
    }
    
    var observers: [ObjectIdentifier: WeakObserver] = [:]
    public func add(observer: PandaAnalyticsObserver) {
        observers[ObjectIdentifier(observer)] = WeakObserver(value: observer)
    }

    public func remove(observer: PandaAnalyticsObserver) {
        observers.removeValue(forKey: ObjectIdentifier(observer))
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
    
    func onAppStoreClientPurchase(productId: String, source: PaymentSource) {
        let receipt: String
        switch appStoreClient.receiptBase64String() {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onError?(Errors.appStoreReceiptError(error))
                }
                return
            case .success(let receiptString):
                receipt = receiptString
        }
        networkClient.verifySubscriptions(user: user, receipt: receipt, source: source) { [weak self] (result) in
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
                    self?.viewControllers.forEach({ $0.value?.tryAutoDismiss()})
                    self?.onPurchase?(productId)
                    self?.onSuccessfulPurchase?()
                    self?.send(event: .successfulPurchase(screenId: source.screenId,
                                                          screenName: source.screenName,
                                                          productId: productId)
                    )
                }
            }
        }
    }
    
    func onAppStoreClientRestore(productIds: [String]) {
        switch appStoreClient.receiptBase64String() {
        case .failure(let error):
            DispatchQueue.main.async {
                self.viewControllers.forEach { $0.value?.onFinishLoad() }
                self.onError?(Errors.appStoreReceiptError(error))
            }
            return
        case .success(let receipt):
            networkClient.verifySubscriptions(user: user, receipt: receipt, source: nil) { _ in }
        }
        DispatchQueue.main.async { [weak self] in
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
            self?.viewControllers.forEach({ $0.value?.tryAutoDismiss()})
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

    public func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, product: String? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        if let screen = cache[screenId] {
            DispatchQueue.main.async {
                callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, product: product)))
            }
            return
        }
        networkClient.loadScreen(user: user, screenId: screenId, screenType: screenType) { [weak self] result in
            guard let self = self else {
                DispatchQueue.main.async {
                    callback?(.failure(Errors.message("Panda is missing!")))
                }
                return
            }
            switch result {
            case .failure(let error):
                guard let defaultScreen = try? NetworkClient.loadScreenFromBundle() else {
                    DispatchQueue.main.async {
                        callback?(.failure(error))
                    }
                    return
                }
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: defaultScreen, screenType: screenType, product: product)))
                }
            case .success(let screen):
                self.cache[screen.id] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, product: product)))
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
        networkClient.verifySubscriptions(user: user, receipt: receipt, source: nil) { (result) in
            callback(result)
        }
    }

    func addViewControllers(controllers: Set<WeakObject<WebViewController>>) {
        let updatedVCs = controllers.compactMap {$0.value}
        updatedVCs.forEach { (vc) in
            vc.viewModel = createViewModel(screenData: vc.viewModel?.screenData ?? ScreenData.default)
        }
        viewControllers.formUnion(updatedVCs.map(WeakObject<WebViewController>.init(value:)))
    }
    
    private func prepareViewController(screen: ScreenData, screenType: ScreenType, product: String? = nil) -> WebViewController {
        send(event: .screenWillShow(screenId: screen.id, screenName: screen.name))
        let viewModel = createViewModel(screenData: screen, product: product)
        let controller = setupWebView(html: screen.html, viewModel: viewModel, screenType: screenType)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func createViewModel(screenData: ScreenData, product: String? = nil) -> WebViewModel {
        let viewModel = WebViewModel(screenData: screenData)
        if let product = product {
            viewModel.product = appStoreClient.products[product]
        }
        viewModel.onSurvey = { answer, screenId, screenName in
            pandaLog("AnswerSelected send: \(answer)")
            self.send(answer: answer, at: screenId, screenName: screenData.name)
        }
        viewModel.onFeedback = { feedback, screenId, screenName in
            pandaLog("Feedback send: \(String(describing: feedback))")
            if let text = feedback {
                self.send(feedback: text, at: screenId)
            }
        }
        viewModel.onPurchase = { [appStoreClient, weak self] productId, source, _, screenId, screenName in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            self?.send(event: .purchaseStarted(screenId: screenId, screenName: screenName, productId: productId))
            appStoreClient.purchase(productId: productId, source: PaymentSource(screenId: screenId, screenName: screenData.name))
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
        viewModel.dismiss = { [weak self] status, view, screenId, screenName in
            pandaLog("Dismiss")
            if let screenID = screenId, let name = screenName {
                self?.trackClickDismiss(screenId: screenID, screenName: name)
            }
            view.tryAutoDismiss()
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
        send(event: .screenShowed(screenId: viewModel.screenData.id,
                                        screenName: viewModel.screenData.name)
        )
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
    
    public func showScreen(screenType: ScreenType, screenId: String? = nil, product: String? = nil, autoDismiss: Bool = true, presentationStyle: UIModalPresentationStyle = .pageSheet, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        if let screen = cache[screenId] {
            self.showPreparedViewController(screenData: screen, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, onShow: onShow)
            return
        }
        networkClient.loadScreen(user: user, screenId: screenId, screenType: screenType) { [weak self] (screenResult) in
            switch screenResult {
            case .failure(let error):
                guard let defaultScreen = try? NetworkClient.loadScreenFromBundle() else {
                    pandaLog("ShowScreen Error: \(error)")
                    onShow?(.failure(error))
                    return
                }
                self?.showPreparedViewController(screenData: defaultScreen, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, onShow: onShow)
            case .success(let screenData):
                self?.cache[screenData.id] = screenData
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, onShow: onShow)
            }
        }
    }
    
    private func showPreparedViewController(screenData: ScreenData, screenType: ScreenType, product: String?, autoDismiss: Bool, presentationStyle: UIModalPresentationStyle, onShow: ((Result<Bool, Error>) -> Void)?) {
        DispatchQueue.main.async {
            let vc = self.prepareViewController(screen: screenData, screenType: screenType, product: product)
            vc.modalPresentationStyle = presentationStyle
            vc.isAutoDismissable = autoDismiss
            self.presentOnRoot(with: vc) {
                onShow?(.success(true))
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
    
    fileprivate func send(answer text: String, at screenId: String?, screenName: String?) {        networkClient.sendAnswers(user: user, screenId: screenId ?? "default", answer: text) { result in
            switch result {
            case .failure(let error):
                pandaLog("Send Answers \(text) text failed: \(error)!")
            case .success(let id):
                pandaLog("Send Answers \(id)")
            }
        }
    }
}

extension PandaProtocol where Self: ObserverSupport {
    
    func openBillingIssue() {
        send(event: .billingDetailsTap)
        openLink(link: ClientConfig.current.billingUrl) { result in
            self.trackOpenLink("billing_issue", result)
        }
    }
    
    func openTerms() {
        send(event: .termsAndConditionsTap)
        openLink(link: ClientConfig.current.termsUrl) { result in
            self.trackOpenLink("terms", result)
        }
    }
    
    func openPolicy() {
        send(event: .privacyPolicyTap)
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
    
    func trackClickDismiss(screenId: String, screenName: String) {
        send(event: .screenDismissed(screenId: screenId, screenName: screenName))
    }

    func copyCallbacks<T: PandaProtocol & ObserverSupport>(from other: T) {
        onPurchase = other.onPurchase
        onRestorePurchases = other.onRestorePurchases
        onError = other.onError
        onDismiss = other.onDismiss
        onSuccessfulPurchase = other.onSuccessfulPurchase
        observers.merge(other.observers, uniquingKeysWith: {(_, new) in new })
    }
}

class ScreenCache {
    var cache: [String: ScreenData] = [:]
    
    subscript(screenId: String?) -> ScreenData? {
        get {
            guard let key = screenId else { return nil }
            return cache[key]
        }
        set(newValue) {
            guard let key = screenId else { return }
            guard let newValue = newValue else {
                cache.removeValue(forKey: key)
                return
            }
            cache[key] = newValue
        }
    }
}

