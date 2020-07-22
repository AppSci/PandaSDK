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
     Initializes PandaSDK. You should call it in `func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool`. All Panda funcs must be  called after Panda is configured
     
     - parameter apiKey: Required. Your api key.
     - parameter isDebug: Optional. Please, use `true` for debugging, `false` for production.
     - parameter callback: Optional. You can do check if Panda SDK in configured.
     */
    func configure(apiKey: String, isDebug: Bool, callback: ((Bool) -> Void)?)
    
    /**
     Returns Panda configuration state
     */
    var isConfigured: Bool {get}
    
    /**
     Register user for recieving Push Notifications
     - parameter token: Token that user recieved after succeeded registration to Push Notifications
     - parameter callback: Optional. Returns If Device Registration was successfull
     */
    func registerDevice(token: Data)
    
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
    
    /**
     You can call to check subscription status of User
    */
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?)
    
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

}

public extension Panda {
    /**
     Shared Panda Instance
     */
    internal(set) static var shared: PandaProtocol = UnconfiguredPanda()
}

extension Panda {
    static func configure(apiKey: String, isDebug: Bool = true, unconfigured: UnconfiguredPanda?, callback: @escaping (Result<Panda, Error>) -> Void) {
        if notificationDispatcher == nil {
            notificationDispatcher = NotificationDispatcher()
        }

        let networkClient = NetworkClient(apiKey: apiKey, isDebug: isDebug)
        let appStoreClient = AppStoreClient()
        
        if let productIds = ClientConfig.current.productIds {
            appStoreClient.fetchProducts(productIds: Set(productIds), completion: {_ in })
        }
        
        let userStorage: Storage<PandaUser> = CodableStorageFactory.userDefaults()
        if let user = userStorage.fetch() {
            callback(.success(create(user: user, networkClient: networkClient, appStoreClient: appStoreClient, unconfigured: unconfigured)))
            return
        }
        networkClient.registerUser() { (result) in
            switch result {
            case .success(let user):
                userStorage.store(user)
                callback(.success(create(user: user, networkClient: networkClient, appStoreClient: appStoreClient, unconfigured: unconfigured)))
            case .failure(let error):
                callback(.failure(error))
            }
        }
    }
    
    static private func create(user: PandaUser, networkClient: NetworkClient, appStoreClient: AppStoreClient, unconfigured: UnconfiguredPanda?) -> Panda {
        let panda = Panda(user: user, networkClient: networkClient, appStoreClient: appStoreClient)
        if let unconfigured = unconfigured {
            panda.copyCallbacks(from: unconfigured)
            panda.addViewControllers(controllers: unconfigured.viewControllers)
        }
        let deviceToken = unconfigured?.deviceToken
        shared = panda
        panda.configureAppStoreClient()
        deviceToken.map(panda.registerDevice(token:))
        Panda.notificationDispatcher.onApplicationDidBecomeActive = panda.onApplicationDidBecomeActive
        return panda
    }

}
