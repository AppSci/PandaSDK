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
    var onRestorePurchase: ((String) -> Void)? { get set }
    
    /**
     Called when purchase failed in Panda purchase screen.
    */
    var onError: ((Error) -> Void)? { get set }
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

final class UnconfiguredPanda: PandaProtocol {
    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        callback?(.failure(Errors.notConfigured))
    }
    func prefetchScreen(screenId: String?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
    }
    var onPurchase: ((String) -> Void)?
    var onRestorePurchase: ((String) -> Void)?
    var onError: ((Error) -> Void)?
}

public extension Panda {
    
    /**
     Initializes PandaSDK. You should call it in `func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool`. All Panda funcs must be  called after Panda is configured
     
     - parameter apiKey: Required. Your api key.
     - parameter isDebug: Optional. Please, use `true` for debugging, `false` for production. Default is `true`.
     - parameter callback: Optional. You can do check if Panda SDK in configured.
     */
    static func configure(token: String, isDebug: Bool = true, callback: ((Bool) -> Void)?) {
        guard shared is UnconfiguredPanda else {
            pandaLog("Already configured")
            callback?(true)
            return
        }

        let networkClient = NetworkClient(isDebug: isDebug)
        let appStoreClient = AppStoreClient()
        
        if let productIds = ClientConfig.current.productIds {
            appStoreClient.fetchProducts(productIds: Set(productIds), completion: {_ in })
        }
        
        let deviceStorage: Storage<RegistredDevice> = CodableStorageFactory.userDefaults()
        if let device = deviceStorage.fetch() {
            shared = Panda(token: token, device: device, networkClient: networkClient, appStoreClient: appStoreClient)
            callback?(true)
            return
        }
        networkClient.registerUser(token: token) { (result) in
            switch result {
            case .success(let device):
                pandaLog(device.id)
                deviceStorage.store(device)
                shared = Panda(token: token, device: device, networkClient: networkClient, appStoreClient: appStoreClient)
                callback?(true)
            case .failure(let error):
                pandaLog("\(error)")
                callback?(false)
            }
        }
    }
}

final public class Panda: PandaProtocol {

    public private(set) static var shared: PandaProtocol = UnconfiguredPanda()
    
    let networkClient: NetworkClient
    let cache: ScreenCache = ScreenCache()
    let token: String
    let device: RegistredDevice
    let appStoreClient: AppStoreClient
    var viewControllers: Set<WeakObject<WebViewController>> = []

    public var onPurchase: ((String) -> Void)?
    public var onRestorePurchase: ((String) -> Void)?
    public var onError: ((Error) -> Void)?
    
    init(token: String, device: RegistredDevice, networkClient: NetworkClient, appStoreClient: AppStoreClient) {
        self.token = token
        self.device = device
        self.networkClient = networkClient
        self.appStoreClient = appStoreClient
        configureAppStoreClient()
    }
    
    internal func configureAppStoreClient() {
        appStoreClient.onError = { [weak self] error in
            self?.onError?(error)
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
        }
        appStoreClient.onPurchase = { [weak self] productId in
            self?.onPurchase?(productId)
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
        }
        appStoreClient.onRestore = { [weak self] productId in
            self?.onRestorePurchase?(productId)
            self?.viewControllers.forEach { $0.value?.onFinishLoad() }
        }
        appStoreClient.startObserving()
    }
    
    public func prefetchScreen(screenId: String?) {
        networkClient.loadScreen(token: token, device: device, screenId: screenId) { [weak self] result in
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
        networkClient.loadScreen(token: token, device: device, screenId: screenId) { [weak self] result in
            guard let self = self else {
                callback?(.failure(Errors.message("Panda is missing!")))
                return
            }
            switch result {
            case .failure(let error):
                //                let res = Result(catching: { try self.networkClient.loadScreenFromBundle() })
                //                    .mapError {_ -> Error in error}
                //                    .map { self.prepareViewController(screen: $0) as UIViewController }
                //                callback?(res)
                
                guard let defaultScreen = try? self.networkClient.loadScreenFromBundle() else {
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
        viewModel.dismiss = { status, view in
            pandaLog("Dismiss")
            self.trackClickDismiss()
            view.dismiss(animated: true, completion: nil)
//            if self.autoDismiss {
//                self.dismiss(view: view)
//            }
        }
        let controller = setupWebView(html: screen.html, viewModel: viewModel)
        viewControllers = viewControllers.filter { $0.value != nil }
        viewControllers.insert(WeakObject(value: controller))
        return controller
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel) -> WebViewController {
        let controller = WebViewController()

//        let urlComponents = setupUrlRequest(state, viewModel.screenName)
//        pandaLog("Panda // WEB URL to load \(urlComponents?.url?.absoluteString ?? "")")
//        controller.url = urlComponents

        controller.view.backgroundColor = .init(red: 91/255, green: 191/255, blue: 186/244, alpha: 1)
        controller.modalPresentationStyle = .overFullScreen
        controller.loadPage(html: html)
        controller.viewModel = viewModel
        return controller
    }

}


extension Panda {
    private func openBillingIssue() {
        openLink(link: ClientConfig.current.billingUrl) { result in
            self.trackOpenLink("billing_issue", result)
        }
    }
    
    private func openTerms() {
        openLink(link: ClientConfig.current.termsUrl) { result in
            self.trackOpenLink("terms", result)
        }
    }
    
    private func openPolicy() {
        openLink(link: ClientConfig.current.policyUrl) { result in
            self.trackOpenLink("policy", result)
        }
    }
    
    private func openLink(link: String, completionHandler completion: ((Bool) -> Void)? = nil) {
        if let url = URL(string: link), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: completion)
        }
    }
}

extension Panda {
    func trackOpenLink(_ link: String, _ result: Bool) {
    }
    
    func trackClickDismiss() {
    }
}
