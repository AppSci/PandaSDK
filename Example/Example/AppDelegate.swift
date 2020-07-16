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
                Panda.shared.prefetchScreen(screenId: "e7ce4093-907e-4be6-8fc5-d689b5265f32")
            }
        }
        return true
    }



}

