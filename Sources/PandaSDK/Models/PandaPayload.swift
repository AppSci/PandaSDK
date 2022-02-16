//
//  PandaPayload.swift
//  PandaSDK
//
//  Created by Aleksey Filobok on 09.02.2022.
//

import Foundation

public struct PandaPayload {
    let shouldShowDefaultScreen: Bool
    let screenBackgroundColor: UIColor?
    let extraEventValues: [String: String]
    let pageLoadingTimeout: TimeInterval
    let htmlDownloadTimeout: TimeInterval?
    let data: [String: Any]?

    init(
        shouldShowDefaultScreen: Bool = true,
        screenBackgroundColor: UIColor? = nil,
        extraEventValues: [String: String] = [:],
        pageLoadingTimeout: TimeInterval = Constants.defaultTimeout,
        htmlDownloadTimeout: TimeInterval? = nil,
        data: [String: Any]? = nil
    ) {
        self.shouldShowDefaultScreen = shouldShowDefaultScreen
        self.screenBackgroundColor = screenBackgroundColor
        self.extraEventValues = extraEventValues
        self.pageLoadingTimeout = pageLoadingTimeout
        self.htmlDownloadTimeout = htmlDownloadTimeout
        self.data = data
    }
}

private enum Constants {
    static let defaultTimeout: TimeInterval = 3.0
}
