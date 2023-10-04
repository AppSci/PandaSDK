//
//  DeviceInfo.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation
import UIKit

enum DeviceInfo {
    static let hardwareIdentifier = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    static let timeZoneIdentifier = TimeZone.current.identifier
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "unknown"
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    static let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    static let executableName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable")as? String ?? "unknown"
    static let osVersion = UIDevice.current.systemVersion
    static let osName = UIDevice.current.systemName
    
    static let userAgent = "\(executableName)/\(version) \(osName)/\(osVersion)"
}
