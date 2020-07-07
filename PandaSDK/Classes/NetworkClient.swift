//
//  NetworkClient.swift
//  Panda
//
//  Created by Kuts on 29.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit

internal struct RegistredDevice: Codable {
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

internal class NetworkClient {
    
    internal static let shared = NetworkClient()
    
    let isDebug: Bool
    let boosterAPI: String
    let networkService: NetworkService
    
    init(networkService: NetworkService, isDebug: Bool = false) {
        self.networkService = networkService
        self.isDebug = isDebug
        self.boosterAPI = isDebug ? Settings.current.serverDebugUrl : Settings.current.serverUrl
    }
    
    convenience init(isDebug: Bool = false) {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.init(networkService: NetworkService(dataLoader: URLSession(configuration: config)), isDebug: isDebug)
    }
        
    internal func loadScreen(token: String, device: RegistredDevice, screenId: String?, callback: ((Result<ScreenData, Error>) -> Void)?) {
        guard var components = URLComponents(string: "https://sdk-api.panda-stage.boosters.company/v1/screen") else {
            callback?(.failure(Errors.message("Error Creating Request. Nil URL?")))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "user", value: device.id),
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

    internal func registerDevice(token: String, callback: ((Result<RegistredDevice, Error>) -> Void)?) {
        guard let url = URL(string: "https://sdk-api.panda-stage.boosters.company/v1/users"),
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
                print(request)
                let error: Error = (try? decoder.decode(ResponseError.self, from: data)) ?? Errors.message("ResponseCode: \(response.statusCode)")
                callback?(.failure(error))
                return
            }
            let device: RegistredDevice
            do {
                device = try decoder.decode(RegistredDevice.self, from: data)
            } catch {
                callback?(.failure(error))
                return
            }
            callback?(.success(device))
        }
    }
    
    func registerUser(token: String, callback: @escaping (Result<RegistredDevice, Error>) -> Void) {
        retry(2, task: { (onComplete) in
            self.registerDevice(token: token, callback: onComplete)
        }, completion: callback)
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
