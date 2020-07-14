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

internal struct ResponseError: Codable, Error {
    let message: String
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

internal class NetworkClient {
    
    internal static let shared = NetworkClient()
    
    let isDebug: Bool
    let serverAPI: String
    let networkService: NetworkService
    
    init(networkService: NetworkService, isDebug: Bool = true) {
        self.networkService = networkService
        self.isDebug = isDebug
        self.serverAPI = isDebug ? ClientConfig.current.serverDebugUrl : ClientConfig.current.serverUrl
    }
    
    convenience init(isDebug: Bool = true) {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.init(networkService: NetworkService(dataLoader: URLSession(configuration: config)), isDebug: isDebug)
    }
        
    internal func loadScreen(token: String, user: PandaUser, screenId: String?, callback: ((Result<ScreenData, Error>) -> Void)?) {
        let boosterScreenURL = serverAPI + "/v1/screen"
        guard var components = URLComponents(string: boosterScreenURL) else {
            callback?(.failure(Errors.message("Error Creating Request. Nil URL?")))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "user", value: user.id),
            URLQueryItem(name: "id", value: screenId),
        ]
        guard let url = components.url, var request = networkService.createRequest(url: url, method: .get) else {
            callback?(.failure(Errors.message("Error Creating Request. Nil URL?")))
            return
        }
    
        request.cachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy
        request.timeoutInterval = 20
        request.setValue(DeviceInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue(token, forHTTPHeaderField: "Authorization")
        if let language = Locale.current.languageCode {
            request.addValue(language, forHTTPHeaderField: "Accept-Language")
        }

        networkService.dataLoader.loadData(using: request) { (data, response, requestError) in
            guard let response = response, let data = data, requestError == nil else {
                callback?(.failure(requestError ?? Errors.message("No data")))
                return
            }

            let decoder = JSONDecoder()
            guard response.statusCode < 400 else {
                print(request)
                let error: Error = (try? decoder.decode(ResponseError.self, from: data)) ?? Errors.message("ResponseCode: \(response.statusCode)")
                callback?(.failure(error))
                return
            }

            let screen: ScreenData
            do {
                screen = try decoder.decode(ScreenData.self, from: data)
            } catch {
                callback?(.failure(error))
                return
            }
            callback?(.success(screen))
        }
    }

    internal func registerUserRequest(token: String, callback: ((Result<PandaUser, Error>) -> Void)?) {
        guard let url = URL(string: serverAPI + "/v1/users"),
            var request = networkService.createRequest(url: url, method: .post) else {
                callback?(.failure(Errors.message("Wrong url")))
                return
        }
        request.cachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy
        request.timeoutInterval = 20
        request.setValue(DeviceInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(token, forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(currentDeviceParameters()) else {
            callback?(.failure(Errors.message("Error encoding parameters.")))
            return
        }
        request.httpBody = data
        networkService.dataLoader.loadData(using: request) { (data, response, requestError) in
            guard let response = response, let data = data, requestError == nil else {
                callback?(.failure(requestError ?? Errors.message("No data")))
                return
            }
            let decoder = JSONDecoder()
            guard response.statusCode < 400 else {
                let error: Error = (try? decoder.decode(ResponseError.self, from: data)) ?? Errors.message("ResponseCode: \(response.statusCode)")
                callback?(.failure(error))
                return
            }
            do {
                let user = try decoder.decode(PandaUser.self, from: data)
                callback?(.success(user))
            } catch {
                callback?(.failure(error))
            }
        }
    }
    
    func verifySubscriptionsRequest(token: String, user: PandaUser, receipt: String, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        guard let url = URL(string: serverAPI + "/v1/itunes/verify/\(user.id)"),
            var request = networkService.createRequest(url: url, method: .post) else {
                callback(.failure(Errors.message("Wrong url")))
                return
        }
        request.cachePolicy = URLRequest.CachePolicy.useProtocolCachePolicy
        request.timeoutInterval = 20
        request.setValue(DeviceInfo.userAgent, forHTTPHeaderField: "User-Agent")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = receipt.data(using: .utf8)
        
        networkService.dataLoader.loadData(using: request) { (data, response, requestError) in
            guard let response = response, let data = data, requestError == nil else {
                callback(.failure(requestError ?? Errors.message("No data")))
                return
            }
            let decoder = JSONDecoder()
            guard response.statusCode < 400 else {
                let error: Error = (try? decoder.decode(ResponseError.self, from: data)) ?? Errors.message("ResponseCode: \(response.statusCode)")
                callback(.failure(error))
                return
            }
            do {
                let result = try decoder.decode(ReceiptVerificationResult.self, from: data)
                callback(.success(result))
            } catch {
                callback(.failure(error))
            }
        }
    }
    
    func verifySubscriptions(token: String, user: PandaUser, receipt: String, retries: Int = 1, callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void) {
        retry(retries, task: { (onComplete) in
            self.verifySubscriptionsRequest(token: token, user: user, receipt: receipt, callback: onComplete)
        }, completion: callback)
    }
    
    func registerUser(token: String, retries: Int = 2, callback: @escaping (Result<PandaUser, Error>) -> Void) {
        retry(retries, task: { (onComplete) in
            self.registerUserRequest(token: token, callback: onComplete)
        }, completion: callback)
    }
    
    func loadScreenFromBundle() throws -> ScreenData {
        guard let fileURL = Bundle.main.url(forResource: "Default", withExtension: "html"), let fileContents = try? String(contentsOf: fileURL) else {
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
