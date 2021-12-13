//
//  PandaUserInfo.swift
//  PandaSDK
//
//  Created by Aleksey Filobok on 04.12.2021.
//

import Foundation

struct PandaUserInfo: Codable {
    let deviceFamily: String = UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"
    let appVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    let deviceModel: String = UIDevice.current.modelName
    let timeZone: String = TimeZone.autoupdatingCurrent.identifier
    let osVersion: String = UIDevice.current.systemVersion
    let locale: String = Locale.current.identifier
    let platform: String = "iOS"
    let country: String? = Locale.current.regionCode
    let language: String? = Locale.current.languageCode
    let idfv: String? = UIDevice.current.identifierForVendor?.uuidString
    let idfa: String? = identifierForAdvertising()
    let pushNotificationToken: String?
    let customUserId: String?
    let appsFlyerId: String?
    let fbc: String?
    let fbp: String?
    let email: String?
    let facebookLoginId: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    let phone: String?
    let gender: Int?
    let userProperties: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case deviceFamily = "device_family"
        case appVersion = "start_app_version"
        case deviceModel = "device_model"
        case timeZone = "time_zone"
        case osVersion = "os_version"
        case locale
        case platform
        case country
        case language
        case idfv
        case idfa
        case pushNotificationToken = "push_notifications_token"
        case customUserId = "custom_user_id"
        case appsFlyerId = "appsflyer_id"
        case fbc
        case fbp
        case email
        case facebookLoginId = "facebook_login_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case username = "user_name"
        case phone
        case gender
        case userProperties = "properties"
    }
    
    init(
        pushNotificationToken: String? = nil,
        customUserId: String? = nil,
        appsFlyerId: String? = nil,
        idfa: String? = nil,
        idfv: String? = nil,
        fbc: String? = nil,
        fbp: String? = nil,
        email: String? = nil,
        facebookLoginId: String? = nil,
        firstName: String? = nil,
        lastName: String? = nil,
        username: String? = nil,
        phone: String? = nil,
        gender: Int? = nil,
        userProperties: [String: String] = [:]
    ) {
        self.pushNotificationToken = pushNotificationToken
        self.customUserId = customUserId
        self.appsFlyerId = appsFlyerId
        self.fbc = fbc
        self.fbp = fbp
        self.email = email
        self.facebookLoginId = facebookLoginId
        self.firstName = firstName
        self.lastName = lastName
        self.username = username
        self.phone = phone
        self.gender = gender
        self.userProperties = userProperties
    }
}

// MARK: - Init Helpers
extension PandaUserInfo {
    static func body(forPandaFacebookId pandaFacebookId: PandaFacebookId) -> Self {
        switch pandaFacebookId {
        case .fbc(let fbc): return .init(fbc: fbc)
        case .fbp(let fbp): return .init(fbp: fbp)
        case .fbpAndFbc(let fbp, let fbc): return .init(fbc: fbc, fbp: fbp)
        case .empty: return .init()
        }
    }
    static func body(forCAPIConfig capiConfig: CAPIConfig) -> Self {
        .init(email: capiConfig.email,
              facebookLoginId: capiConfig.facebookLoginId,
              firstName: capiConfig.firstName,
              lastName: capiConfig.lastName,
              username: capiConfig.username,
              phone: capiConfig.phone,
              gender: capiConfig.gender)
    }
    static func body(forUserProperties userProperties: Set<PandaUserProperty>) -> Self {
        let keyValueDictionary = userProperties.reduce(into: [String: String]()) { result, userProperty in
            result[userProperty.key] = userProperty.value
        }
        
        return .init(userProperties: keyValueDictionary)
    }
}
