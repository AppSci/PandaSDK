//
//  UnconfiguredPanda.swift
//  PandaSDK
//
//  Created by Kuts on 20.07.2020.
//

import Foundation

final class UnconfiguredPanda: PandaProtocol {
    var onPurchase: ((String) -> Void)?
    var onRestorePurchases: (([String]) -> Void)?
    var onError: ((Error) -> Void)?
    var onDismiss: (() -> Void)?
    
    private var viewControllers: Set<WeakObject<WebViewController>> = []
    
    struct LastConfigurationAttempt {
        var token: String
        var isDebug: Bool
    }
    private var lastConfigurationAttempt: LastConfigurationAttempt?

    func configure(token: String, isDebug: Bool = true, callback: ((Result<Panda, Error>) -> Void)?) {
        lastConfigurationAttempt = LastConfigurationAttempt(token: token, isDebug: isDebug)
        let networkClient = NetworkClient(token: token, isDebug: isDebug)
        let appStoreClient = AppStoreClient()
        
        if let productIds = ClientConfig.current.productIds {
            appStoreClient.fetchProducts(productIds: Set(productIds), completion: {_ in })
        }
        
        let userStorage: Storage<PandaUser> = CodableStorageFactory.userDefaults()
        if let user = userStorage.fetch() {
            callback?(.success(Panda(user: user, networkClient: networkClient, appStoreClient: appStoreClient, copyCallbacks: self)))
            return
        }
        networkClient.registerUser() { [weak self] (result) in
            switch result {
            case .success(let user):
                userStorage.store(user)
                callback?(.success(Panda(user: user, networkClient: networkClient, appStoreClient: appStoreClient, copyCallbacks: self)))
            case .failure(let error):
                callback?(.failure(error))
            }
        }
    }

    func prefetchScreen(screenId: String?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
    }

    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?,
                               screenCallback: ((Result<UIViewController, Error>) -> Void)?) {
        pandaLog("Please, configure Panda, by calling Panda.configure(\"<API_TOKEN>\")")
        statusCallback?(.failure(Errors.notConfigured))
    }

    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?) {
        let defaultScreen: ScreenData
        do {
            defaultScreen = try NetworkClient.loadScreenFromBundle()
        } catch {
            callback?(.failure(error))
            return
        }
        DispatchQueue.main.async {
            callback?(.success(self.prepareViewController(screen: defaultScreen)))
        }
    }
    
    func show(screen screenId: String? = nil, type screenType: ScreenType = .promo, callback: ((Result<Bool, Error>) -> Void)?) {
        DispatchQueue.main.async {
            callback?(.success(false))
        }
    }
    
    func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) {
        print("deeplinks handler")
    }
    
    private func reconfigure(callback: @escaping (Result<Panda, Error>) -> Void) {
        guard let configAttempt = lastConfigurationAttempt else {
            viewControllers.forEach { $0.value?.onFinishLoad() }
            callback(.failure(Errors.notConfigured))
            return
        }
        configure(token: configAttempt.token, isDebug: configAttempt.isDebug) { [viewControllers] (result) in
            switch result {
            case .success(let panda):
                panda.addViewControllers(controllers: viewControllers)
                Panda.shared = panda
            case .failure:
                viewControllers.forEach { $0.value?.onFinishLoad() }
            }
            callback(result)
        }
    }

    private func prepareViewController(screen: ScreenData) -> WebViewController {
        let viewModel = WebViewModel()
        viewModel.screenName = screen.id
        viewModel.onSurvey = { value in
            pandaLog("Survey: \(value)")
        }
        viewModel.onPurchase = { [weak self] productId, source, view in
            guard let productId = productId else {
                pandaLog("Missing productId with source: \(source)")
                return
            }
            self?.reconfigure(callback: { (result) in
                switch result {
                case .success:
                    pandaLog("Reconfigured")
                    view.viewModel?.onPurchase?(productId, source, view)
                case .failure(let error):
                    pandaLog("Reconfigured error: \(error)")
                    DispatchQueue.main.async {
                        view.showInternetConnectionAlert()
                        self?.viewControllers.forEach { $0.value?.onFinishLoad() }
                    }
                    self?.onError?(error)
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
                    }
                    self?.onError?(error)
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

