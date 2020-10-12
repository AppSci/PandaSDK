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
     Returns screen from Panda Web
     - parameter screenId: Optional. ID screen. If `nil` - returns default screen from Panda Web
     - parameter callback: Optional. Returns Result for getting screen
     */
    func getScreen(screenId: String?, callback: ((Result<UIViewController, Error>) -> Void)?)
    
    func getScreen(screenType: ScreenType, screenId: String?, product: String?, callback: ((Result<UIViewController, Error>) -> Void)?)
    
    /**
     Returns screen with specific product from Panda Web
     - parameter screenType: Required. Screen Type.
     - parameter product: Optional. product ID. If `nil` - returns default screen from Panda Web without detailed product info
     - parameter onShow: Optional. Returns Result for showing screen
     */
    func showScreen(screenType: ScreenType, screenId: String?, product: String?, onShow: ((Result<Bool, Error>) -> Void)?)
    
    func showScreen(screenType: ScreenType, screenId: String?, product: String?, autoDismiss: Bool, presentationStyle: UIModalPresentationStyle, onShow: ((Result<Bool, Error>) -> Void)?)

    /**
     Prefetches screen from Panda Web - if you want to cashe Screen before displaying it
     - parameter screenId: Optional. ID screen. If `nil` - returns default screen from Panda Web
     */
    func prefetchScreen(screenId: String?)
    
    /**
     You can call to check subscription status of User
    */
    func getSubscriptionStatus(statusCallback: ((Result<SubscriptionStatus, Error>) -> Void)?)
    
    /**
        Handle deeplinks
     */
    func handleApplication(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any])

    // MARK: - Handle Push Notification
    
    /**
     Register user for recieving Push Notifications
     - parameter token: Token that user recieved after succeeded registration to Push Notifications
     - parameter callback: Optional. Returns If Device Registration was successful
     */
    func registerDevice(token: Data)
    
    /**
     Call this method in the corresponding UNUserNotificationCenterDelegate method.
     - returns: true, if notification presentation was handled by Panda. We'll call completionHanlder in that case. false - you need to process notification presentation and call completionHandler by yourself.
     ~~~
     extension AppDelegate: UNUserNotificationCenterDelegate {
         func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
             if Panda.shared.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) {
                 return
             }
             completionHandler([])
         }
     }
     ~~~
     */
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) -> Bool
    
    /**
     Call this method in the corresponding UNUserNotificationCenterDelegate method.
     - returns: true, if notification presentation was handled by Panda. We'll call completionHanlder in that case. false - you need to process notification presentation and call completionHandler by yourself.
     ~~~
     extension AppDelegate: UNUserNotificationCenterDelegate {
         func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
             if Panda.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) {
                 return
             }
             completionHandler()
         }
     }
     ~~~
     */
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) -> Bool

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
     Called on screen close attempt after successful purchase or restore.
    */
    var onSuccessfulPurchase: (() -> Void)? { get set }

    /**
     Call this func for users that already purchased subscription BEFORE Panda
     You can call this func only once, on first user session
     */
    func verifySubscriptions(callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void)
    
    func add(observer: PandaAnalyticsObserver)
    func remove(observer: PandaAnalyticsObserver)
}

public extension PandaProtocol {
    /**
     Default implementation without callback, screenId, product
     Returns screen with specific product from Panda Web
     - parameter screenType: Required. Screen Type.
     - parameter product: Optional. product ID. If `nil` - returns default screen from Panda Web without detailed product info
     - parameter callback: Optional. Returns Result for showing screen
     */
    func showScreen(screenType: ScreenType, screenId: String? = nil, product: String? = nil, onShow: ((Result<Bool, Error>) -> Void)? = nil) {
        showScreen(screenType: screenType, screenId: screenId, product: product, autoDismiss: true, presentationStyle: .pageSheet, onShow: onShow)
    }
    
    /**
     Default implementation without callback & screenId
     Returns screen from Panda Web
     - parameter screenId: Optional. ID screen. If `nil` - returns default screen from Panda Web
     - parameter callback: Optional. Returns Result for getting screen
     */

    func getScreen(screenId: String? = nil, callback: ((Result<UIViewController, Error>) -> Void)?) {
        getScreen(screenType: .sales, screenId: screenId, product: nil, callback: callback)
    }
    
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
        let appStoreClient = AppStoreClient(storage: CodableStorageFactory.userDefaults())
        
        if let productIds = ClientConfig.current.productIds {
            appStoreClient.fetchProducts(productIds: Set(productIds), completion: {_ in })
        }
        
        let userStorage: Storage<PandaUser> = CodableStorageFactory.keychain()
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

    static public func resetPandaStorage() {
        let userStorage: Storage<PandaUser> = CodableStorageFactory.keychain()
        userStorage.clear()
    }
}
