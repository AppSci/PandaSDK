//
//  AppDelegate.swift
//  Example
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 PandaSDK. All rights reserved.
//

import UIKit
import PandaSDK

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {


    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Panda.shared.onPurchase = { result in print("onRestorePurchases: \(result)") }
        Panda.shared.onRestorePurchases = { result in print("onRestorePurchases: \(result)") }
        Panda.shared.onError = { result in print("onError: \(result)") }
        Panda.shared.onDismiss = { print("onDismiss") }
        // Override point for customization after application launch.
        Panda.configure(token: "V8F4HCl5Wj6EPpiaaa7aVXcAZ3ydQWpS", isDebug: true) { (configured) in
            print("Configured: \(configured)")
            if configured {
                Panda.shared.prefetchScreen(screenId: "e7ce4093-907e-4be6-8fc5-d689b5265f32")
            }
        }
        return true
    }


    func applicationDidBecomeActive(_ application: UIApplication) {
//        Panda.shared.getSubscriptionStatus(statusCallback: { (subscriptionResult) in
//            switch subscriptionResult {
//            case .failure(let error):
//                print("Subscription status failed with error: \(error)")
//            case .success(let subscriptionStatus):
//                print("Subscription status is: \(subscriptionStatus.rawValue)")
//            }
//        }) { (screenResult) in
//
//        }
    }

}

// MARK: UIApplication extensions

extension UIApplication {

    class func getTopViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {

        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)

        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)

        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }
}
