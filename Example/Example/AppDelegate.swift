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
        Panda.configure(token: "fqT3OgopCeLRDG8jb5EJ843UgSAGAjfH", isDebug: true) { (configured) in
            print("Configured: \(configured)")
            if configured {
                Panda.shared.prefetchScreen(screenId: "5f0a4b61-3460-4c1a-817e-141d0bb5eb03")
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
