//
//  WeakObject.swift
//  PandaSDK
//
//  Created by Kuts on 04.07.2020.
//

import Foundation

struct DeviceSettings: Codable {
    var pushToken: String
    var advertisementIdentifier: String
    var appsFlyerId: String
    var customUserId: String
    var fbp: String
    var fbc: String
    
    static let `default` = DeviceSettings(pushToken: "",
                                          advertisementIdentifier: "",
                                          appsFlyerId: "",
                                          customUserId: "",
                                          fbp: "",
                                          fbc: "")
}
