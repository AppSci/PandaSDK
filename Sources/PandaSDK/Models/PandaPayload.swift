//
//  PandaPayload.swift
//  PandaSDK
//
//  Created by Aleksey Filobok on 09.02.2022.
//

import UIKit

public struct PandaPayload {
    internal let shouldShowDefaultScreen: Bool
    internal let screenBackgroundColor: UIColor?
    internal let entryPoint: String?
    internal let pageLoadingTimeout: TimeInterval
    internal let htmlDownloadTimeout: TimeInterval?
    internal let data: [String: Any]?

    public init(
        shouldShowDefaultScreen: Bool = true,
        screenBackgroundColor: UIColor? = nil,
        entryPoint: String? = nil,
        pageLoadingTimeout: TimeInterval = 3.0,
        htmlDownloadTimeout: TimeInterval? = nil,
        targetLanguage: String? = nil,
        fromLanguage: String? = nil,
        strings: [[String: String]]? = nil,
        lessonTitle: String? = nil,
        lessonKey: String? = nil,
        courseID: String? = nil,
        lessonRate: String? = nil,
        customId: String? = nil,
        email: String? = nil
    ) {
        self.shouldShowDefaultScreen = shouldShowDefaultScreen
        self.screenBackgroundColor = screenBackgroundColor
        self.entryPoint = entryPoint
        self.pageLoadingTimeout = pageLoadingTimeout
        self.htmlDownloadTimeout = htmlDownloadTimeout
        var data: [String: Any] = [:]
        if let targetLanguage = targetLanguage {
            data["target_language"] = targetLanguage
        }
        if let fromLanguage = fromLanguage {
            data["from_language"] = fromLanguage
        }

        if let strings = strings {
            data["strings"] = strings
        }

        if let lessonTitle = lessonTitle {
            data["lesson_title"] = lessonTitle
        }

        if let lessonKey = lessonKey {
            data["lesson_key"] = lessonKey
        }

        if let courseID = courseID {
            data["course_id"] = courseID
        }

        if let lessonRate = lessonRate {
            data["lesson_rate"] = lessonRate
        }

        if let customId = customId {
            data["custom_id"] = customId
        }

        if let email = email {
            data["email"] = email
        }

        self.data = data
    }
}
