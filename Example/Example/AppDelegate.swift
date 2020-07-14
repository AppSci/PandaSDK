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
        // Override point for customization after application launch.
        Panda.configure(token: "V8F4HCl5Wj6EPpiaaa7aVXcAZ3ydQWpS", isDebug: true) { (configured) in
            print("Configured: \(configured)")
            if configured {
                Panda.shared.prefetchScreen(screenId: "0fe27e07-a104-48bc-b558-e5afce061c3a")
            }
        }
        return true
    }



}

