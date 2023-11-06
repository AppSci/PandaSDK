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
import StoreKit

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
    private let cache: ScreenCache = ScreenCache()
    let user: PandaUser
    let appStoreService: AppStoreService

    var verificationClient: VerificationClient
    private let settingsStorage: Storage<Settings> = CodableStorageFactory.userDefaults()
    private let deviceStorage: Storage<DeviceSettings> = CodableStorageFactory.userDefaults()
    var viewControllers: Set<WeakObject<WebViewController>> = []
    var viewControllerForApplePayPurchase: WebViewController?
    private var payload: PandaPayload?
    var entryPoint: String? {
        return payload?.entryPoint
    }
    var observers: [ObjectIdentifier: WeakObserver] = [:]
    
    public var onPurchase: ((Product) -> Void)?
    public var shouldAddStorePayment: ((SKProduct) -> Bool)?
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
        appStoreService: AppStoreService,
        applePayPaymentHandler: ApplePayPaymentHandler,
        webAppId: String?
    ) {
        self.user = user
        self.networkClient = networkClient
        self.appStoreService = appStoreService
        self.verificationClient = networkClient
        self.applePayPaymentHandler = applePayPaymentHandler
        self.pandaUserId = user.id
        self.webAppId = webAppId
        bindApplePayMessages()
    }
    
    func configureAppStoreService() {
        appStoreService.onVerify = onAppStoreServiceVerify
        appStoreService.onTransaction = onAppStoreServiceTransaction
        appStoreService.startTask()
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

    public func getScreen(screenType: ScreenType = .sales, screenId: String? = nil, productID: String? = nil, payload: PandaPayload? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        self.payload = payload
        if let screen = cache[screenId] {
            DispatchQueue.main.async {
                callback?(
                    .success(
                        self.prepareViewController(
                            screen: screen,
                            screenType: screenType,
                            productID: productID,
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
                                productID: productID,
                                payload: payload
                            )
                        )
                    )
                }

            case .success(let screen):
                self.cache[screen.id.string] = screen
                DispatchQueue.main.async {
                    callback?(.success(self.prepareViewController(screen: screen, screenType: screenType, productID: productID, payload: payload)))
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
        let productID = url.pathComponents[safe: 2]
        
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

        showScreen(screenType: screenType, screenId: screen, productID: productID)
    }
    
    public func verifySubscriptions() async throws -> ReceiptVerificationResult {
        try await appStoreService.verifyTransaction(user: user, source: nil)
    }
    
    public func purchase(productID: String, screenName: String) async throws {
        let paymentSource = PaymentSource(screenId: "", screenName: screenName, course: "")
        try await purchase(productID: productID, paymentSource: paymentSource)
    }
    
    public func purchase(productID: String, paymentSource: PaymentSource) async throws {
        do {
            let purchaseResult = try await appStoreService.purchase(
                productID: productID,
                source: paymentSource
            )
            switch purchaseResult {
            case let .success(_, product):
                try await Task.sleep(seconds: 1)
                send(event: .onPandaWillVerify(
                    screenId: paymentSource.screenId,
                    screenName: paymentSource.screenName,
                    productId: product.id
                ))
                _ = try await self.appStoreService.verifyTransaction(
                    user: self.user,
                    source: paymentSource
                )
                await self.onVerified(product: product, source: paymentSource)
            case .cancelled, .pending:
                await self.onCancel()
            }
        } catch {
            await self.onError(error: error)
            throw error
        }
    }
    
    public func restorePurchase() {
        Task {
            try await appStoreService.restore()
        }
    }
    
    func addViewControllers(controllers: Set<WeakObject<WebViewController>>) {
        let updatedVCs = controllers.compactMap {$0.value}
        updatedVCs.forEach { (vc) in
            vc.viewModel = createViewModel(screenData: vc.viewModel?.screenData ?? ScreenData.unknown)
        }
        viewControllers.formUnion(updatedVCs.map(WeakObject<WebViewController>.init(value:)))
    }
    
    private func prepareViewController(screen: ScreenData, screenType: ScreenType, productID: String? = nil, payload: PandaPayload? = nil) -> WebViewController {
        let viewModel = createViewModel(screenData: screen, productID: productID, payload: payload)
        let controller = setupWebView(html: screen.html, viewModel: viewModel, screenType: screenType)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
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
    
    public func showScreen(
        screenType: ScreenType,
        screenId: String? = nil,
        productID: String? = nil,
        autoDismiss: Bool = true, 
        presentationStyle: UIModalPresentationStyle = .pageSheet,
        payload: PandaPayload? = nil,
        onShow: ((Result<Bool, Error>) -> Void)? = nil
    ) {
        self.payload = payload
        if let screen = cache[screenId] {
            self.showPreparedViewController(screenData: screen, screenType: screenType, productID: productID, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
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
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, productID: productID, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            case .success(let screenData):
                self?.cache[screenData.id.string] = screenData
                self?.showPreparedViewController(screenData: screenData, screenType: screenType, productID: productID, autoDismiss: autoDismiss, presentationStyle: presentationStyle, payload: payload, onShow: onShow)
            }
        }
    }
    
    private func showPreparedViewController(screenData: ScreenData, screenType: ScreenType, productID: String?, autoDismiss: Bool, presentationStyle: UIModalPresentationStyle, payload: PandaPayload? = nil, onShow: ((Result<Bool, Error>) -> Void)?) {
        DispatchQueue.main.async {
            let vc = self.prepareViewController(screen: screenData, screenType: screenType, productID: productID, payload: payload)
            vc.modalPresentationStyle = presentationStyle
            vc.isAutoDismissable = autoDismiss
            self.presentOnRoot(with: vc) {
                onShow?(.success(true))
            }
        }
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
    
    public func forceUpdateUser(completion: @escaping (Result<String, Error>) -> Void) {
        let data = deviceStorage.fetch()
        guard let data else {
            return
        }
        let pandaUserInfo = PandaUserInfo(
            pushNotificationToken: data.pushToken,
            customUserId: data.customUserId,
            appsFlyerId: data.appsFlyerId,
            fbc: data.pandaFacebookId.fbc ?? "",
            fbp: data.pandaFacebookId.fbp ?? "",
            email: data.capiConfig.email ?? "",
            facebookLoginId: data.capiConfig.facebookLoginId ?? "",
            firstName: data.capiConfig.firstName ?? "",
            lastName: data.capiConfig.lastName ?? "",
            username: data.capiConfig.username ?? "",
            phone: data.capiConfig.phone ?? "",
            gender: data.capiConfig.gender,
            userProperties: data.userProperties.reduce(into: [String: String]()) { $0[$1.key] = $1.value }
        )
        networkClient.updateUser(user: self.user, pandaUserInfo: pandaUserInfo) { result in
            completion(result.map { $0.id })
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
