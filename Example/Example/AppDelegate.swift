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
class AppDelegate: UIResponder, UIApplicationDelegate, PandaAnalyticsObserver {


    var window: UIWindow?

    func handle(event: PandaEvent) {
        print(event)
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Panda.shared.add(observer: self)
        Panda.shared.configure(apiKey: "9QBqG5Kcxyvo2F8Pzwz27xrPsf1miVZ6", isDebug: false) { (status) in
            print("Configured: \(status)")
            if status {
                Panda.shared.prefetchScreen(screenId: "a1fc1e19-6d20-4b73-b95f-3b66e53e1b51")
            }
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }

            }
        }
        Panda.shared.verifySubscriptions { (result) in
             switch result {
             case .failure(let error):
                 print("Error: \(error)")
             case .success(let verificationResult):
                 print("Verification result: \(verificationResult)")
             }
         }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("REGISTRED \(deviceToken)")
        Panda.shared.registerDevice(token: deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("REGISTRATION ERROR \(error)")
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if Panda.shared.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) {
            return
        }
        completionHandler([])
    }

    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if Panda.shared.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) {
            return
        }
        completionHandler()
    }
}
