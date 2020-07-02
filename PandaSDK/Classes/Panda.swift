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
    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?)
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
}

public extension Panda {
    static func configure(token: String = "V8F4HCl5Wj6EPpiaaa7aVXcAZ3ydQWpS", isDebug: Bool = false, callback: ((Bool) -> Void)?) {
        guard shared is UnconfiguredPanda else {
            pandaLog("Already configured")
            callback?(true)
            return
        }
        let networkClient = NetworkClient(isDebug: isDebug)
        let deviceStorage: Storage<RegistredDevice> = CodableStorageFactory.userDefaults()
//        if let device = deviceStorage.fetch() {
//            shared = Panda(token: token, device: device, networkClient: networkClient)
//            callback?(true)
//            return
//        }
        networkClient.registerDevice(token: token) { (result) in
            switch result {
            case .success(let device):
                pandaLog(device.id)
                deviceStorage.store(device)
                shared = Panda(token: token, device: device, networkClient: networkClient)
                callback?(true)
            case .failure(let error):
                pandaLog(error.localizedDescription)
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

    init(token: String, device: RegistredDevice, networkClient: NetworkClient) {
        self.token = token
        self.device = device
        self.networkClient = networkClient
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
                callback?(.failure(error))
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
        viewModel.onPurchase = { product, source in
            pandaLog("Purchase: \(product?.description ?? "") \(source)")
        }
        viewModel.onRestorePurchase = {
            pandaLog("Restore")
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
        return controller
    }
    
    private func setupWebView(html: String, viewModel: WebViewModel) -> WebViewController {
        let controller = WebViewController()

//        let urlComponents = setupUrlRequest(state, viewModel.screenName)
//        pandaLog("Panda // WEB URL to load \(urlComponents?.url?.absoluteString ?? "")")
//        controller.url = urlComponents

        controller.view.backgroundColor = .init(red: 91/255, green: 191/255, blue: 186/244, alpha: 1)
        controller.loadPage(html: html)
        controller.viewModel = viewModel
        return controller
    }

}


extension Panda {
    private func openBillingIssue() {
        openLink(link: Settings.current.billingUrl) { result in
            self.trackOpenLink("billing_issue", result)
        }
    }
    
    private func openTerms() {
        openLink(link: Settings.current.termsUrl) { result in
            self.trackOpenLink("terms", result)
        }
    }
    
    private func openPolicy() {
        openLink(link: Settings.current.policyUrl) { result in
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
