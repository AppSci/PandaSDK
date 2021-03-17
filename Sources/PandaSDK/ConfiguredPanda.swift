//
//  ConfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 22.07.2020.
//

import Foundation
import UIKit

protocol VerificationClient {
    func verifySubscriptions(user: PandaUser, receipt: String, source: PaymentSource?, retries: Int, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void)
}

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
    var verificationClient: VerificationClient
    private let settingsStorage: Storage<Settings> = CodableStorageFactory.userDefaults()
    private let deviceStorage: Storage<DeviceSettings> = CodableStorageFactory.userDefaults()
    private var viewControllers: Set<WeakObject<WebViewController>> = []

    public var onPurchase: ((String) -> Void)?
    public var onRestorePurchases: (([String]) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onDismiss: (() -> Void)?
    public var onSuccessfulPurchase: (() -> Void)?
    public let isConfigured: Bool = true
    public var pandaUserId: String?

    init(user: PandaUser, networkClient: NetworkClient, appStoreClient: AppStoreClient) {
        self.user = user
        self.networkClient = networkClient
        self.appStoreClient = appStoreClient
        self.verificationClient = networkClient
        self.pandaUserId = user.id
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
            self.send(event: .purchaseError(error: error))
        }
    }
    
    func onAppStoreClientPurchase(productId: String, source: PaymentSource) {
        let receipt: String
        switch appStoreClient.receiptBase64String() {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onError?(Errors.appStoreReceiptError(error))
                    self.send(event: .purchaseError(error: error))
                }
                return
            case .success(let receiptString):
                receipt = receiptString
        }
        verificationClient.verifySubscriptions(user: user, receipt: receipt, source: source, retries: 1) { [weak self] (result) in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    self?.onError?(Errors.appStoreReceiptError(error))
                    self?.send(event: .purchaseError(error: error))
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
                self.send(event: .purchaseError(error: error))
            }
            return
        case .success(let receipt):
            verificationClient.verifySubscriptions(user: user, receipt: receipt, source: nil, retries: 1) { [weak self] (result) in
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                        self?.onError?(Errors.appStoreReceiptError(error))
                        self?.send(event: .purchaseError(error: error))
                    }
                case .success(let verification):
                    DispatchQueue.main.async { [weak self] in
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                        self?.viewControllers.forEach({ $0.value?.tryAutoDismiss()})
                        self?.onRestorePurchases?(productIds)
                    }
                }
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

    public func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, product: String? = nil, payload: [String: Any]? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        if let screen = cache[screenId] {
            DispatchQueue.main.async {
                callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, product: product, payload: payload)))
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
                    callback?(.success(self.prepareViewController(screen: defaultScreen, screenType: screenType, product: product, payload: payload)))
                }
            case .success(let screen):
                self.cache[screen.id] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, product: product, payload: payload)))
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
                let subscriptionStatus = SubscriptionStatus(with: apiResponse)
                statusCallback?(.success(subscriptionStatus))
            }
        }
    }


    public func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any]) {
        
        guard url.host == "panda" else { return }
        
        /// track analytics
        trackDeepLink(url.relativeString)

        /// appid://panda/promo/product_id?screen_id=xxxxxxx-xxxxx-xxxx-xxxxxx
        
        /// get screen type
        let type = url.pathComponents[safe: 1]
        
        /// get product_id safety
        let product = url.pathComponents[safe: 2]
        
        /// get screen_id sefety
        let screen = url.components?.queryItems?["screen_id"]
        
        var screenType = ScreenType.promo
        
        switch type {
        case "sales":
            screenType = .sales
        case "product":
            screenType = .product
        default:
            screenType = .promo
        }

        showScreen(screenType: screenType, screenId: screen, product: product)
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
        verificationClient.verifySubscriptions(user: user, receipt: receipt, source: nil, retries: 1) { (result) in
            callback(result)
        }
    }
    
    public func purchase(productID: String) {
        appStoreClient.purchase(productId: productID, source: PaymentSource(screenId: "", screenName: "manual purchase"))
    }
    
    public func restorePurchase() {
        appStoreClient.restore()
    }

    func addViewControllers(controllers: Set<WeakObject<WebViewController>>) {
        let updatedVCs = controllers.compactMap {$0.value}
        updatedVCs.forEach { (vc) in
            vc.viewModel = createViewModel(screenData: vc.viewModel?.screenData ?? ScreenData.default)
        }
        viewControllers.formUnion(updatedVCs.map(WeakObject<WebViewController>.init(value:)))
    }
    
    private func prepareViewController(screen: ScreenData, screenType: ScreenType, product: String? = nil, payload: [String: Any]? = nil) -> WebViewController {
        let viewModel = createViewModel(screenData: screen, product: product, payload: payload)
        let controller = setupWebView(html: screen.html, viewModel: viewModel, screenType: screenType)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func createViewModel(screenData: ScreenData, product: String? = nil, payload: [String: Any]? = nil) -> WebViewModel {
        let viewModel = WebViewModel(screenData: screenData, payload: payload)
        if let product = product {
            appStoreClient.getProduct(with: product) { result in
                switch result {
                case .failure(let error):
                    pandaLog("\(error.localizedDescription)")
                case .success(let product):
                    viewModel.product = product
                }
            }
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
            pandaLog("purchaseStarted: \(productId) \(screenName) \(screenId)")
            self?.send(event: .purchaseStarted(screenId: screenId, screenName: screenName, productId: productId))
            appStoreClient.purchase(productId: productId, source: PaymentSource(screenId: screenId, screenName: screenData.name))
        }
        viewModel.onRestorePurchase = { [appStoreClient] _ in
            pandaLog("Restore")
            appStoreClient.restore()
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
                self?.trackClickDismiss(screenId: screenID, screenName: name)
            }
            view.tryAutoDismiss()
            self?.onDismiss?()
        }
        viewModel.onViewWillAppear = { [weak self] screenId, screenName in
            pandaLog("onViewWillAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenWillShow(screenId: screenId ?? "", screenName: screenName ?? ""))
        }
        viewModel.onViewDidAppear = { [weak self] screenId, screenName in
            pandaLog("onViewDidAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenLoaded(screenId: screenId ?? "", screenName: screenName ?? ""))
        }
        viewModel.onDidFinishLoading = { [weak self] screenId, screenName in
            pandaLog("onDidFinishLoading \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenShowed(screenId: screenId ?? "", screenName: screenName ?? ""))
        }
        return viewModel
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel, screenType: ScreenType) -> WebViewController {
        let controller = WebViewController()

        controller.view.backgroundColor = viewModel.payload?["background"] as? UIColor
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
            let status: SubscriptionState
            switch result {
            case .failure(let error):
                pandaLog("SubscriptionStatus Error: \(error)")
                return
            case .success(let value):
                status = value.state
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
    
    public func showScreen(screenType: ScreenType, screenId: String? = nil, product: String? = nil, autoDismiss: Bool = true, presentationStyle: UIModalPresentationStyle = .pageSheet, payload: [String: Any]? = nil, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        if let screen = cache[screenId] {
            self.showPreparedViewController(screenData: screen, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
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
                self?.showPreparedViewController(screenData: defaultScreen, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            case .success(let screenData):
                self?.cache[screenData.id] = screenData
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            }
        }
    }
    
    private func showPreparedViewController(screenData: ScreenData, screenType: ScreenType, product: String?, autoDismiss: Bool, presentationStyle: UIModalPresentationStyle, payload: [String: Any]? = nil, onShow: ((Result<Bool, Error>) -> Void)?) {
        DispatchQueue.main.async {
            let vc = self.prepareViewController(screen: screenData, screenType: screenType, product: product, payload: payload)
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
    
    public func setCustomUserId(id: String) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.customUserId != id else {
            print("Already sent custom user id")
            return
        }
        device.customUserId = id
        deviceStorage.store(device)
        networkClient.updateUser(user: user, with: id) { result in
            switch result {
            case .failure(let error):
                pandaLog("Error on set custom user id: \(error)")
            case .success:
                pandaLog("Set custom id success")
            }
        }
    }
    
    public func registerDevice(token: Data) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.pushToken != token.hexString() else {
            print("Already sent apnsToken")
            return
        }
        device.pushToken = token.hexString()
        deviceStorage.store(device)
        networkClient.updateUser(pushToken: token.hexString(), user: user) { (result) in
            switch result {
            case .failure(let error):
                pandaLog("Register device error: \(error)")
            case .success:
                pandaLog("Device registred")
            }
        }
    }
    
    public func registerAppsFlyer(id: String) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.appsFlyerId != id else {
            print("Already sent apnsToken")
            return
        }
        device.appsFlyerId = id
        deviceStorage.store(device)
        networkClient.updateUser(appsFlyerId: id, user: user) { (result) in
            switch result {
            case .failure(let error):
                pandaLog("Appsflyer not configured error: \(error)")
            case .success:
                pandaLog("Appsflyer configured")
            }
        }
    }
    
    public func registerIDFA(id: String) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.advertisementIdentifier != id else {
            print("Already sent advertisementIdentifier")
            return
        }
        device.advertisementIdentifier = id
        deviceStorage.store(device)
        networkClient.updateUser(advertisementId: id, user: user) { (result) in
            switch result {
            case .failure(let error):
                pandaLog("ATTrackingManager not configured error: \(error)")
            case .success:
                pandaLog("ATTrackingManager configured")
            }
        }
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
    
    func openSubscriptionTerms() {
        send(event: .subscriptionTermsTap)
        openLink(link: ClientConfig.current.subscriptionUrl) { result in
            self.trackOpenLink("subscription terms", result)
        }
    }
    
    func openLink(link: String, completionHandler completion: ((Bool) -> Void)? = nil) {
        if let url = URL(string: link), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }

    func trackOpenLink(_ link: String, _ result: Bool) {
        send(event: .trackOpenLink(link: link, result: "\(result)"))
    }

    func trackDeepLink(_ link: String) {
        send(event: .trackDeepLink(link: link))
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

extension NetworkClient: VerificationClient {
    
}
