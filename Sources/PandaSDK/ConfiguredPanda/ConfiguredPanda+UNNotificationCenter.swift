//
//  ConfiguredPanda+UNNotificationCenter.swift
//
//
//  Created by Denys Danyliuk on 06.09.2023.
//

import UIKit

extension Panda {
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) -> Bool {
        guard pandaEvent(notification: notification) != nil else {
            return false
        }
        completionHandler([.list, .banner])
        return true
    }
    
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) -> Bool {
        guard let status = pandaEvent(notification: response.notification) else {
            return false
        }
        switch status {
        case "canceled", "disabled_auto_renew":
            if UIApplication.shared.applicationState == .active {
                showScreen(screenType: .survey)
            }
        default:
            break
        }
        completionHandler()
        return true
    }
    
    private func pandaEvent(notification: UNNotification) -> String? {
        notification.request.content.userInfo["panda-event"] as? String
    }
}
