//
//  NetworkClient.swift
//  Panda
//
//  Created by Kuts on 29.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit

internal struct PandaUser: Codable {
    let id: String
}

internal struct SubscriptionStatusResponse: Codable {
    let state: SubscriptionAPIStatus
}

internal struct ScreenData: Codable {
    let id: String
    let name: String
    let html: String
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case html = "screen_html"
    }
}

internal struct ReceiptVerificationResult: Codable {
    let id: String
    let active: Bool
}

enum SubscriptionAPIStatus: String, Codable {
    case success
    case empty
    case refund
    case canceled
    case disabledAutoRenew
    case billing
    
    enum CodingKeys: String, CodingKey {
        case success = "ok"
        case empty
        case refund
        case canceled
        case disabledAutoRenew = "disabled_auto_renew"
        case billing = "failed_renew"
    }
}

public enum SubscriptionStatus: String {
    case success
    case empty
    case refund
    case canceled
    case billing
    
    public init?(rawValue: String) {
        switch rawValue {
        case "ok":
            self = .success
        case "empty":
            self = .empty
        case "refund":
            self = .refund
        case "canceled", "disabled_auto_renew":
            self = .canceled
        case "failed_renew":
            self = .billing
        default:
            return nil
        }
    }
    
    init(with subscriptionAPIstatus: SubscriptionAPIStatus) {
        switch subscriptionAPIstatus {
        case .success:
            self = .success
        case .billing:
            self = .billing
        case .refund:
            self = .refund
        case .canceled, .disabledAutoRenew:
            self = .canceled
        case .empty:
            self = .empty
        }
    }
    
}

public enum ScreenType: String, Codable {
    case sales
    case promo
    case billing
    case survey
    case feedback
}

internal class NetworkClient {
    
    let isDebug: Bool
    let serverAPI: String
    let networkLoader: NetworkLoader

    enum HttpMethod: String {
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }

    private init(networkLoader: NetworkLoader, isDebug: Bool = true) {
        self.networkLoader = networkLoader
        self.isDebug = isDebug
        self.serverAPI = isDebug ? ClientConfig.current.serverDebugUrl : ClientConfig.current.serverUrl
    }
    
    convenience init(token: String, isDebug: Bool = true) {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": DeviceInfo.userAgent,
            "Content-Type": "application/json",
            "Authorization": token
        ]
        config.urlCache = nil
        self.init(networkLoader: URLSession(configuration: config), isDebug: isDebug)
    }
    
    internal func loadScreen(user: PandaUser, screenId: String?, screenType: ScreenType? = .sales, callback: @escaping ((Result<ScreenData, Error>) -> Void)) {
        let request = createRequest(path: "/v1/screen",
                                    method: .get,
                                    query: [
                                        "user": user.id,
                                        "id": screenId,
                                        "type": screenType?.rawValue,
                                    ],
                                    headers: [
                                        "Accept-Language": Locale.current.languageCode
                                    ])
        
        networkLoader.loadData(with: request, completion: callback)
    }
    
    internal func registerUserRequest(callback: @escaping (Result<PandaUser, Error>) -> Void) {
        let request = createRequest(path: "/v1/users",
                                    method: .post,
                                    body: currentDeviceParameters()
        )
        networkLoader.loadData(with: request, completion: callback)
    }

    func verifySubscriptionsRequest(user: PandaUser, receipt: String, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        let request = createRequest(path: "/v1/itunes/verify/\(user.id)",
                                    method: .post,
                                    httpBody: receipt.data(using: .utf8))
        networkLoader.loadData(with: request, completion: callback)
    }
    
    func getSubscriptionStatus(user: PandaUser, callback: @escaping (Result<SubscriptionStatusResponse, Error>) -> Void) {
        let request = createRequest(path: "/v1/subscription-status/\(user.id)",
                                    method: .get)
        networkLoader.loadData(with: request, completion: callback)
    }
    
    func updateUser(pushToken: String, user: PandaUser, callback: @escaping (Result<PandaUser, Error>) -> Void) {
        let request = createRequest(path: "/v1/users/\(user.id)",
                                    method: .put,
                                    body: currentUserParameters(pushToken: pushToken))
        networkLoader.loadData(with: request, completion: callback)
    }
    
    func verifySubscriptions(user: PandaUser, receipt: String, retries: Int = 1, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        retry(retries, task: { (onComplete) in
            self.verifySubscriptionsRequest(user: user, receipt: receipt, callback: onComplete)
        }, completion: callback)
    }

    func registerUser(retries: Int = 2, callback: @escaping (Result<PandaUser, Error>) -> Void) {
        retry(retries, task: { (onComplete) in
            self.registerUserRequest(callback: onComplete)
        }, completion: callback)
    }
    
    func createRequest(path: String, method: HttpMethod, query: [String: String?]? = nil, headers: [String: String?]? = nil, httpBody: Data? = nil) -> Result<URLRequest, Error> {
        guard var components = URLComponents(string: serverAPI + path) else {
            return .failure(Errors.message("Bad url: \(serverAPI + path)"))
        }
        components.queryItems = query?.compactMap { query in query.value.map { URLQueryItem(name: query.key, value: $0) } }
        guard let url = components.url else {
            return .failure(Errors.message("Bad url: \(serverAPI + path)\n\(components)"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = httpBody
        headers?.compactMapValues {$0}.forEach({ header in
            request.setValue(header.value, forHTTPHeaderField: header.key)
        })
        return .success(request)
    }
    
    func createRequest<T: Codable>(path: String, method: HttpMethod, query: [String: String?]? = nil, headers: [String: String?]? = nil, body: T) -> Result<URLRequest, Error> {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(body)
            return createRequest(path: path, method: method, query: query, headers: headers, httpBody: data)
        } catch {
            return .failure(error)
        }
    }

    static func loadScreenFromBundle(name: String = "Default") throws -> ScreenData {
        guard let fileURL = Bundle.main.url(forResource: name, withExtension: "html"), let fileContents = try? String(contentsOf: fileURL) else {
            throw Errors.message("Cannot find default screen html")
        }
        let screenData = ScreenData(id: "default", name: "default", html: fileContents)
        return screenData
    }
}

func retry<T>(_ attempts: Int,
              interval: DispatchTimeInterval = .seconds(0),
              task: @escaping (_ completion:@escaping (Result<T, Error>) -> Void) -> Void,
              completion: @escaping (Result<T, Error>) -> Void) {
    
    task({ result in
        switch result {
        case .success:
            completion(result)
        case .failure(let error):
            guard attempts > 0 else {
                completion(result)
                return
            }
            print("retries left \(attempts) and error = \(error)")
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                retry(attempts - 1, interval: interval, task: task, completion: completion)
            }
        }
    })
}

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
