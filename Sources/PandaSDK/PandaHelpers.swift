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
