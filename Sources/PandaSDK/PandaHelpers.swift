//
//  PandaHelpers.swift
//  Panda
//
//  Created by Kuts on 30.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit
import AdSupport

internal func currentDeviceParameters() -> [String: String] {

//    {
//      "country": "string",
//      "device_model": "string",
//      "app_version": "string",
//      "start_app_version": "string",
//      "timezone": "string",
//      "os_version": "string",
//      "idfa": "string",
//      "device_family": "string",
//      "language": "string",
//      "locale": "string",
//      "platform": "string",
//      "push_notifications_token": "string",
//      "custom_user_id": "string",
//      "idfv": "string"
//    }
    
    let family: String
    if UIDevice.current.userInterfaceIdiom == .phone {
        family = "iPhone"
    } else {
        family = "iPad"
    }
    let app_version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""

    var params: [String: String] = [
        "device_model": UIDevice.current.modelName,
        "app_version": app_version,
        "start_app_version": app_version,
        "time_zone": TimeZone.autoupdatingCurrent.identifier,
        "os_version": UIDevice.current.systemVersion,
        "device_family": family,
        "locale": Locale.current.identifier,
        "platform": "iOS",
    ]

    if let regionCode = Locale.current.regionCode {
        params["country"] = regionCode.uppercased()
    }
    if let language = Locale.current.languageCode {
        params["language"] = language
    }
    if let idfv = UIDevice.current.identifierForVendor?.uuidString {
        params["idfv"] = idfv
    }

    if let idfa = identifierForAdvertising() {
        params["idfa"] = idfa
    }

    return params
}

internal func currentUserParameters(pushToken: String? = nil,
                                    customUserId: String? = nil,
                                    appsFlyerId: String? = nil,
                                    advertisementId: String? = nil,
                                    facebookIds: FacebookIds? = nil) -> [String: String] {
    var currentParameters = currentDeviceParameters()
    if let pushToken = pushToken {
        currentParameters["push_notifications_token"] = pushToken
    }
    if let customUserId = customUserId {
        currentParameters["custom_user_id"] = customUserId
    }
    if let appsFlyerId = appsFlyerId {
        currentParameters["appsflyer_id"] = appsFlyerId
    }
    if let advertisementId = advertisementId {
        currentParameters["idfa"] = advertisementId
    }
    if let fbc = facebookIds?[.fbc] {
        currentParameters["fbc"] = fbc
    }
    if let fbp = facebookIds?[.fbp] {
        currentParameters["fbp"] = fbp
    }
    return currentParameters
}

internal func identifierForAdvertising() -> String? {
    if #available(iOS 14, *) {
        // Get and return IDFA
        return ASIdentifierManager.shared().advertisingIdentifier.uuidString
    } else {
        // Check whether advertising tracking is enabled
        guard ASIdentifierManager.shared().isAdvertisingTrackingEnabled else {
            return nil
        }
        // Get and return IDFA
        return ASIdentifierManager.shared().advertisingIdentifier.uuidString
    }
}

extension UIDevice {
    var modelName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

internal func pandaLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    print("PandaSDK >>> \(function) \(line) \(file) <<<\nPandaSDK >>> \(message) <<<")
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

extension SubscriptionStatus {
    static func pandaEvent(from notification: UNNotification) -> SubscriptionState? {
        guard let subscriptionAPIStatus = (notification.request.content.userInfo["panda-event"] as? String)
            .flatMap(SubscriptionAPIStatus.init(rawValue: )) else {
                return nil
        }
        return SubscriptionState(with: subscriptionAPIStatus)
    }
}
