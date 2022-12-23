//
//  ConfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 22.07.2020.
//

import Foundation
import UIKit
import Combine
import PassKit

protocol VerificationClient {
    func verifySubscriptions(user: PandaUser, receipt: String, source: PaymentSource?, retries: Int, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void)
    func verifyApplePayRequest(user: PandaUser, paymentData: Data, billingID: String, webAppId: String, callback: @escaping (Result<ApplePayResult, Error>) -> Void)
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
    let applePayPaymentHandler: ApplePayPaymentHandler
    let cache: ScreenCache = ScreenCache()
    let user: PandaUser
    let appStoreClient: AppStoreClient
    var verificationClient: VerificationClient
    private let settingsStorage: Storage<Settings> = CodableStorageFactory.userDefaults()
    private let deviceStorage: Storage<DeviceSettings> = CodableStorageFactory.userDefaults()
    private var viewControllers: Set<WeakObject<WebViewController>> = []
    private var viewControllerForApplePayPurchase: WebViewController?
    private var payload: PandaPayload?
    private var entryPoint: String? {
        return payload?.entryPoint
    }
    
    public var onPurchase: ((String) -> Void)?
    public var onRestorePurchases: (([String]) -> Void)?
    public var onError: ((Error) -> Void)?
    public var onDismiss: (() -> Void)?
    public var onSuccessfulPurchase: (() -> Void)?
    public let isConfigured: Bool = true
    public var pandaUserId: String?
    public var pandaCustomUserId: String? {
        let device = deviceStorage.fetch() ?? DeviceSettings.default
        return device.customUserId
    }
    public var webAppId: String?
    private var cancellable = Set<AnyCancellable>()

    init(
        user: PandaUser,
        networkClient: NetworkClient,
        appStoreClient: AppStoreClient,
        applePayPaymentHandler: ApplePayPaymentHandler,
        webAppId: String?
    ) {
        self.user = user
        self.networkClient = networkClient
        self.appStoreClient = appStoreClient
        self.verificationClient = networkClient
        self.applePayPaymentHandler = applePayPaymentHandler
        self.pandaUserId = user.id
        self.webAppId = webAppId
        bindApplePayMessages()
    }
    
    private func bindApplePayMessages() {
        applePayPaymentHandler.outputPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure = completion {
                    self?.handleApplePayError(errorMessage: "failed to present apple pay screen")
                }
            } receiveValue: { [weak self] message in
                self?.handleApplePay(message)
            }
            .store(in: &cancellable)
    }

    private func handleApplePayError(errorMessage: String) {
        DispatchQueue.main.async { [weak self] in
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
            self?.viewControllerForApplePayPurchase?.dismiss(animated: true) { [weak self] in
                self?.viewControllers.forEach { $0.value?.tryAutoDismiss() }
                self?.send(
                    event: .purchaseError(
                        error: ApplePayVerificationError(message: errorMessage),
                        source: self?.entryPoint
                    )
                )
            }
        }
    }

    private func handleApplePay(_ message: ApplePayPaymentHandlerOutputMessage) {
        switch message {
        case .failedToPresentPayment:
            handleApplePayError(errorMessage: "failed to present apple pay screen")
        case let .paymentFinished(status, billingID, paymentData, productID, screenID):
            guard
                let webAppId = webAppId,
                status == PKPaymentAuthorizationStatus.success
            else {
                handleApplePayError(errorMessage: "Payment finished unsuccessfully")

                return
            }

            send(event: .onStartApplePayProcess)
            viewControllers.forEach { $0.value?.onStartLoad() }

            verificationClient.verifyApplePayRequest(
                user: user,
                paymentData: paymentData,
                billingID: billingID,
                webAppId: webAppId
            ) { [weak self] result in

                switch result {
                case let .success(result):
                    if let transactionStatus = result.transactionStatus,
                       transactionStatus == .fail {
                        self?.handleApplePayError(errorMessage: "Payment transaction failed")

                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }

                        self?.viewControllerForApplePayPurchase?.dismiss(animated: true) { [weak self] in
                            self?.viewControllers.forEach { $0.value?.tryAutoDismiss() }
                            self?.send(event: .onApplePaySuccessfulPurchase(productID: productID, screenID: screenID))
                        }

                    }
                case let .failure(error):
                    self?.handleApplePayError(errorMessage: error.localizedDescription)
                }
            }
        }
    }
    
    internal func configureAppStoreClient() {
        appStoreClient.onError = { [weak self] error in
            self?.onAppStoreClient(error: error)
        }
        appStoreClient.onPurchase = { [weak self] productId, source in
            self?.onAppStoreClientPurchase(productId: productId, source: source)
        }
        appStoreClient.onRestore = { [weak self] productIds, source in
            self?.onAppStoreClientRestore(productIds: productIds, source: source)
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

    public func configure(apiKey: String, isDebug: Bool, applePayConfiguration: ApplePayConfiguration?, webAppId: String?, callback: ((Bool) -> Void)?) {
        pandaLog("Already configured")
        callback?(true)
    }
    
    func onAppStoreClient(error: Error) {
        DispatchQueue.main.async {
            self.viewControllers.forEach { $0.value?.onFinishLoad() }
            self.onError?(error)
            self.send(event: .purchaseError(error: error, source: self.entryPoint))
        }
    }
    
    func onAppStoreClientPurchase(productId: String, source: PaymentSource) {
        let receipt: String
        switch appStoreClient.receiptBase64String() {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.onError?(Errors.appStoreReceiptError(error))
                    self.send(event: .purchaseError(error: error, source: self.entryPoint))
                }
                return
            case .success(let receiptString):
                receipt = receiptString
        }
        self.send(event: .onPandaWillVerify(screenId: source.screenId, screenName: source.screenName, productId: productId))
        verificationClient.verifySubscriptions(user: user, receipt: receipt, source: source, retries: 1) { [weak self] (result) in
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    self?.onError?(Errors.appStoreReceiptError(error))
                    self?.send(event: .purchaseError(error: error, source: self?.entryPoint))
                }
            case .success(let verification):

                pandaLog("productId = \(productId)\nid = \(verification.id)")
                DispatchQueue.main.async {
                    self?.viewControllers.forEach({ $0.value?.onPurchaseCompleted()})
                    self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    self?.viewControllers.forEach({ $0.value?.tryAutoDismiss()})
                    self?.onPurchase?(productId)
                    self?.onSuccessfulPurchase?()
                    self?.send(
                        event: .successfulPurchase(
                            screenId: source.screenId,
                            screenName: source.screenName,
                            productId: productId,
                            source: self?.entryPoint,
                            course: source.course
                        )
                    )
                }
            }
        }
    }
    
    func onAppStoreClientRestore(productIds: [String], source: PaymentSource) {
        switch appStoreClient.receiptBase64String() {
        case .failure(let error):
            DispatchQueue.main.async {
                self.viewControllers.forEach { $0.value?.onFinishLoad() }
                self.onError?(Errors.appStoreReceiptRestoreError(error))
                self.send(event: .purchaseError(error: error, source: self.entryPoint))
            }
            return
        case .success(let receipt):
            verificationClient.verifySubscriptions(user: user, receipt: receipt, source: source, retries: 1) { [weak self] (result) in
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                        self?.onError?(Errors.appStoreRestoreError(error))
                        self?.send(event: .purchaseError(error: error, source: self?.entryPoint))
                    }
                case .success(let verification):
                    DispatchQueue.main.async { [weak self] in
                        if verification.active {
                            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                            self?.viewControllers.forEach({ $0.value?.tryAutoDismiss()})
                            self?.onRestorePurchases?(productIds)
                        } else {
                            DispatchQueue.main.async {
                                let e = Errors.message("Subscription isn't active")
                                let error = Errors.appStoreRestoreError(e)
                                self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                                self?.onError?(error)
                                self?.send(event: .purchaseError(error: error, source: self?.entryPoint))
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func prefetchScreen(screenId: String?, payload: PandaPayload?) {
        self.payload = payload
        networkClient.loadScreen(user: user, screenId: screenId, timeout: payload?.htmlDownloadTimeout) { [weak self] result in
            guard let self = self else {
                pandaLog("Panda is missing!")
                return
            }
            switch result {
            case .failure(let error):
                self.send(event: .screenShowFailed(screenId: screenId ?? "", screenType: nil))
                pandaLog("Prefetch \(screenId ?? "default") screen failed: \(error)!")
            case .success(let screen):
                self.cache[screenId] = screen
                pandaLog("Prefetched \(screenId ?? "default")")
            }
        }
    }

    public func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, product: String? = nil, payload: PandaPayload? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        self.payload = payload
        if let screen = cache[screenId] {
            DispatchQueue.main.async {
                callback?(
                    .success(
                        self.prepareViewController(
                            screen: screen,
                            screenType: screenType,
                            product: product,
                            payload: payload
                        )
                    )
                )
            }
            return
        }
        
        let shouldShowDefaultScreenOnFailure = payload?.shouldShowDefaultScreen == true
        
        networkClient.loadScreen(user: user, screenId: screenId, screenType: screenType, timeout: payload?.htmlDownloadTimeout) { [weak self] result in
            guard let self = self else {
                DispatchQueue.main.async {
                    callback?(.failure(Errors.message("Panda is missing!")))
                }
                return
            }
            switch result {
            case .failure(let error):
                self.send(event: .screenShowFailed(screenId: screenId ?? "", screenType: screenType.rawValue))
                guard let screenData = ScreenData.default, shouldShowDefaultScreenOnFailure else {
                    DispatchQueue.main.async {
                        callback?(.failure(error))
                    }
                    return
                }
                DispatchQueue.main.async {
                    callback?(
                        .success(
                            self.prepareViewController(
                                screen: screenData,
                                screenType: screenType,
                                product: product,
                                payload: payload
                            )
                        )
                    )
                }

            case .success(let screen):
                self.cache[screen.id.string] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, product: product, payload: payload)))
                }
            }
        }
    }
    
    public func getSubscriptionStatus(withDelay: Double, statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + withDelay) { [weak self] in
            guard
                let self = self
            else {
                return
            }

            self.networkClient.getSubscriptionStatus(user: self.user) { (result) in
                switch result {
                case .failure(let error):
                    statusCallback?(.failure(error))
                case .success(let apiResponse):
                    let subscriptionStatus = SubscriptionStatus(with: apiResponse)
                    statusCallback?(.success(subscriptionStatus))
                }
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
        appStoreClient.purchase(productId: productID, source: PaymentSource(screenId: "", screenName: "manual purchase", course: ""))
    }
    
    public func restorePurchase() {
        appStoreClient.restore(with: PaymentSource(screenId: "", screenName: "manual restore", course: ""))
    }

    func addViewControllers(controllers: Set<WeakObject<WebViewController>>) {
        let updatedVCs = controllers.compactMap {$0.value}
        updatedVCs.forEach { (vc) in
            vc.viewModel = createViewModel(screenData: vc.viewModel?.screenData ?? ScreenData.unknown)
        }
        viewControllers.formUnion(updatedVCs.map(WeakObject<WebViewController>.init(value:)))
    }
    
    private func prepareViewController(screen: ScreenData, screenType: ScreenType, product: String? = nil, payload: PandaPayload? = nil) -> WebViewController {
        let viewModel = createViewModel(screenData: screen, product: product, payload: payload)
        let controller = setupWebView(html: screen.html, viewModel: viewModel, screenType: screenType)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }

    private func createViewModel(screenData: ScreenData, product: String? = nil, payload: PandaPayload? = nil) -> WebViewModel {
        let viewModel = WebViewModel(screenData: screenData, payload: payload)
        let entryPoint = payload?.entryPoint

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
        viewModel.onApplePayPurchase = { [applePayPaymentHandler, weak self] pandaID, source, screenId, screenName, view in
            guard
                let pandaID = pandaID
            else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            self?.viewControllerForApplePayPurchase = view

            pandaLog("purchaseStarted: \(pandaID) \(screenName) \(screenId)")
            self?.send(event: .purchaseStarted(screenId: screenId, screenName: screenName, productId: pandaID, source: entryPoint))

            self?.networkClient.getBillingPlan(
                with: pandaID,
                callback: { result in
                    switch result {
                    case let .success(billingPlan):
                        applePayPaymentHandler.startPayment(
                            with: billingPlan.getLabelForApplePayment(),
                            price: billingPlan.getPrice(),
                            currency: billingPlan.currency,
                            billingID: billingPlan.id,
                            countryCode: billingPlan.countryCode,
                            productID: billingPlan.productID,
                            screenID: screenId
                        )
                    case let .failure(error):
                        self?.onError?(error)
                        self?.send(event: .purchaseError(error: error, source: self?.entryPoint))
                        pandaLog("Failed get billingPlan Error: \(error)")
                    }
                }
            )

        }
        viewModel.onPurchase = { [appStoreClient, weak self] productId, source, _, screenId, screenName, course in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            pandaLog("purchaseStarted: \(productId) \(screenName) \(screenId)")
            self?.send(event: .purchaseStarted(screenId: screenId, screenName: screenName, productId: productId, source: entryPoint))
            appStoreClient.purchase(productId: productId, source: PaymentSource(screenId: screenId, screenName: screenData.name, course: course))
        }
        viewModel.onRestorePurchase = { [appStoreClient] _, screenId, screenName in
            pandaLog("Restore")
            appStoreClient.restore(with: PaymentSource(screenId: screenId ?? "", screenName: screenName ?? "", course: nil))
        }
        viewModel.onCustomEvent = { [weak self] eventName, eventParameters in
            self?.send(event: .customEvent(name: eventName, parameters: eventParameters))
        }
        
        viewModel.onTerms = openTerms
        viewModel.onPolicy = openPolicy
        viewModel.onSubscriptionTerms = openSubscriptionTerms
        viewModel.onPricesLoaded = { [weak self] productIds, view in
            self?.appStoreClient.fetchProducts(productIds: Set(productIds)) { result in
                switch result {
                case let .success(products):
                    view.sendLocalizedPrices(products: products)
                case let .failure(error):
                    pandaLog("Failed to fetch AppStore products, \(error)")
                }
            }
        }
        viewModel.onBillingIssue = { view in
            pandaLog("onBillingIssue")
            self.openBillingIssue()
            view.dismiss(animated: true, completion: nil)
        }
        viewModel.dismiss = { [weak self] status, view, screenId, screenName in
            pandaLog("Dismiss")
            if let screenID = screenId, let name = screenName {
                self?.trackClickDismiss(screenId: screenID, screenName: name, source: entryPoint)
            }
            view.tryAutoDismiss()
            self?.onDismiss?()
        }
        viewModel.onViewWillAppear = { [weak self] screenId, screenName in
            pandaLog("onViewWillAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenWillShow(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint))
        }
        viewModel.onViewDidAppear = { [weak self] screenId, screenName, course in
            pandaLog("onViewDidAppear \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenShowed(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint, course: course))
        }
        viewModel.onDidFinishLoading = { [weak self] screenId, screenName, course in

            pandaLog("onDidFinishLoading \(String(describing: screenName)) \(String(describing: screenId))")
            self?.send(event: .screenLoaded(screenId: screenId ?? "", screenName: screenName ?? "", source: entryPoint))
        }

        viewModel.onSupportUkraineAnyButtonTap = { [weak self] in
            self?.send(event: .onSupportUkraineAnyButtonTap)
        }
        
        viewModel.onDontHaveApplePay = { [weak self]  screenID, destination in
            self?.send(event: .onDontHaveApplePay(screenId: screenID ?? "", source: entryPoint, destination: destination))
        }
        
        viewModel.onTutorsHowOfferWorks = { [weak self]  screenID, destination in
            self?.send(event: .onTutorsHowOfferWorks(screenId: screenID ?? "", source: entryPoint, destination: destination))
        }
                
        return viewModel
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel, screenType: ScreenType) -> WebViewController {
        let controller = WebViewController()

        controller.view.backgroundColor = viewModel.payload?.screenBackgroundColor
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
        getSubscriptionStatus(withDelay: 3.0) { [weak self, settingsStorage] (result) in
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
    
    public func showScreen(
        screenType: ScreenType,
        screenId: String? = nil,
        product: String? = nil,
        autoDismiss: Bool = true, 
        presentationStyle: UIModalPresentationStyle = .pageSheet,
        payload: PandaPayload? = nil,
        onShow: ((Result<Bool, Error>) -> Void)? = nil
    ) {
        self.payload = payload
        if let screen = cache[screenId] {
            self.showPreparedViewController(screenData: screen, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            return
        }
        let shouldShowDefaultScreenOnFailure = payload?.shouldShowDefaultScreen == true
        networkClient.loadScreen(user: user, screenId: screenId, screenType: screenType, timeout: payload?.htmlDownloadTimeout) { [weak self] (screenResult) in
            switch screenResult {
            case .failure(let error):
                self?.send(event: .screenShowFailed(screenId: screenId ?? "", screenType: screenType.rawValue))
                guard screenType == .sales || screenType == .product || screenType == .promo else {
                    pandaLog("ShowScreen Error: \(error)")
                    onShow?(.failure(error))
                    return
                }
                guard let screenData = ScreenData.default, shouldShowDefaultScreenOnFailure else {
                    pandaLog("ShowScreen Error: \(error)")
                    onShow?(.failure(error))
                    return
                }
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            case .success(let screenData):
                self?.cache[screenData.id.string] = screenData
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, product: product, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            }
        }
    }
    
    private func showPreparedViewController(screenData: ScreenData, screenType: ScreenType, product: String?, autoDismiss: Bool, presentationStyle: UIModalPresentationStyle, payload: PandaPayload? = nil, onShow: ((Result<Bool, Error>) -> Void)?) {
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
            pandaLog("Already sent custom user id")
            return
        }
        networkClient.updateUser(user: user, with: id) { [weak self] result in
            switch result {
            case .failure(let error):
                pandaLog("Error on set custom user id: \(error)")
            case .success:
                device.customUserId = id
                self?.deviceStorage.store(device)
                pandaLog("Set custom id success")
            }
        }
    }
    
    public func registerDevice(token: Data) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.pushToken != token.hexString() else {
            pandaLog("Already sent apnsToken")
            return
        }
        networkClient.updateUser(pushToken: token.hexString(), user: user) { [weak self] (result) in
            switch result {
            case .failure(let error):
                pandaLog("Register device error: \(error)")
            case .success:
                device.pushToken = token.hexString()
                self?.deviceStorage.store(device)
                pandaLog("Device registred")
            }
        }
    }
    
    public func registerAppsFlyer(id: String) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.appsFlyerId != id else {
            pandaLog("Already sent apnsToken")
            return
        }
        networkClient.updateUser(appsFlyerId: id, user: user) { [weak self] (result) in
            switch result {
            case .failure(let error):
                pandaLog("Appsflyer not configured error: \(error)")
            case .success:
                device.appsFlyerId = id
                self?.deviceStorage.store(device)
                pandaLog("Appsflyer configured")
            }
        }
    }
    
    public func registerIDFA(id: String) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.advertisementIdentifier != id else {
            pandaLog("Already sent advertisementIdentifier")
            return
        }
        networkClient.updateUser(advertisementId: id, user: user) { [weak self] (result) in
            switch result {
            case .failure(let error):
                pandaLog("ATTrackingManager not configured error: \(error)")
            case .success:
                device.advertisementIdentifier = id
                self?.deviceStorage.store(device)
                pandaLog("ATTrackingManager configured")
            }
        }
    }
    
    public func resetIDFVAndIDFA() {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        networkClient.updateUser(user: user, idfv: "", idfa: "") { [weak self] (result) in
            switch result {
            case .failure(let error):
                pandaLog("reset idfv and idfa error: \(error)")
            case .success:
                device.advertisementIdentifier = ""
                self?.deviceStorage.store(device)
                pandaLog("reset idfa and idfv success")
            }
        }
    }
    
    public func setPandaFacebookId(pandaFacebookId: PandaFacebookId) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        guard device.pandaFacebookId != pandaFacebookId else {
            pandaLog("Already sent Facebook Browser ID and Click ID")
            return
        }
        networkClient.updateUser(user: user, pandaFacebookId: pandaFacebookId) { [weak self] result in
            switch result {
            case .failure(let error):
                pandaLog("Error on set Facebook Browser ID or Click ID: \(error)")
            case .success:
                device.pandaFacebookId = pandaFacebookId
                self?.deviceStorage.store(device)
                pandaLog("Set Facebook Browser ID and Click ID success")
            }
        }
    }
    
    public func register(facebookLoginId: String?, email: String?, firstName: String?, lastName: String?, username: String?, phone: String?, gender: Int?) {
        let capiConfig = CAPIConfig(email: email,
                                    facebookLoginId: facebookLoginId,
                                    firstName: firstName,
                                    lastName: lastName,
                                    username: username,
                                    phone: phone,
                                    gender: gender)
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        let updatedConfig = device.capiConfig.updated(with: capiConfig)
        guard device.capiConfig != updatedConfig else {
            pandaLog("Already sent this capi config: \(capiConfig)")
            return
        }
        networkClient.updateUser(user: user, capiConfig: capiConfig) { [weak self] result in
            switch result {
            case .failure(let error):
                pandaLog("update capi config error: \(error.localizedDescription)")
            case .success:
                device.capiConfig = updatedConfig
                self?.deviceStorage.store(device)
                pandaLog("Success on update capiConfig: \(capiConfig)")
            }
        }
    }
    
    public func setUserProperty(_ pandaUserProperty: PandaUserProperty) {
        setUserProperties([pandaUserProperty])
    }
    
    public func setUserProperties(_ pandaUserProperties: Set<PandaUserProperty>) {
        var device = deviceStorage.fetch() ?? DeviceSettings.default
        var storedUserProperties = device.userProperties
        var shouldUpdate: Bool = false
        pandaUserProperties.forEach { pandaUserProperty in
            let existUserProperty = storedUserProperties.first(where: { $0 == pandaUserProperty })
            if (existUserProperty != nil && existUserProperty?.value != pandaUserProperty.value) ||
                (!storedUserProperties.contains(pandaUserProperty)) {
                shouldUpdate = true
                storedUserProperties.update(with: pandaUserProperty)
            }
        }
        
        guard shouldUpdate else {
            return
        }
        
        networkClient.updateUser(user: user, with: pandaUserProperties) { [weak self] result in
            switch result {
            case .failure(let error):
                pandaLog("update capi config error: \(error.localizedDescription)")
            case .success:
                device.userProperties = storedUserProperties
                self?.deviceStorage.store(device)
                pandaLog("Success on update pandaUserProperty: \(result)")
            }
        }
    }
    
    public func getUserProperties() -> [PandaUserProperty] {
        Array((deviceStorage.fetch() ?? DeviceSettings.default).userProperties)
    }
    
    public func fetchRemoteUserProperties(completion: @escaping((Set<PandaUserProperty>) -> Void)) {
        networkClient.getUser(user: self.user) { [weak self] result in
            let userProperties: Set<PandaUserProperty>
            switch result {
            case .success(let userInfo):
                userProperties = userInfo.userProperties.reduce(into: Set<PandaUserProperty>()) { result, keyValuePair in
                    result.update(with: PandaUserProperty(key: keyValuePair.key, value: keyValuePair.value))
                }
            case .failure:
                userProperties = Set(self?.getUserProperties() ?? [])
            }
            DispatchQueue.main.async {
                completion(userProperties)
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
    
    fileprivate func send(answer text: String, at screenId: String?, screenName: String?) {
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

    func trackClickDismiss(screenId: String, screenName: String, source: String?) {
        send(event: .screenDismissed(screenId: screenId, screenName: screenName, source: source))
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
