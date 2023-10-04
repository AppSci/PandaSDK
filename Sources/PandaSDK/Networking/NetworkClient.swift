//
//  NetworkClient.swift
//  Panda
//
//  Created by Kuts on 29.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation
import UIKit

final class NetworkClient: VerificationClient {
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
    
    convenience init(apiKey: String, isDebug: Bool = true) {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": DeviceInfo.userAgent,
            "Content-Type": "application/json",
            "Authorization": apiKey
        ]
        config.urlCache = nil
        self.init(networkLoader: URLSession(configuration: config), isDebug: isDebug)
    }
    
    func createRequest(
        path: String,
        method: HttpMethod,
        query: [String: String?]? = nil,
        headers: [String: String?]? = nil,
        httpBody: Data? = nil
    ) -> Result<URLRequest, Error> {
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
    
    func createRequest<T: Codable>(
        path: String,
        method: HttpMethod,
        query: [String: String?]? = nil,
        headers: [String: String?]? = nil,
        body: T
    ) -> Result<URLRequest, Error> {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(body)
            return createRequest(path: path, method: method, query: query, headers: headers, httpBody: data)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - Requests
extension NetworkClient {
    internal func loadScreen(
        user: PandaUser,
        screenId: String?,
        screenType: ScreenType? = .sales,
        timeout: TimeInterval?,
        callback: @escaping ((Result<ScreenData, Error>) -> Void)
    ) {
        let request = createRequest(
            path: "/v1/screen",
            method: .get,
            query: [
                "user": user.id,
                "id": screenId,
                "type": screenType?.rawValue
            ],
            headers: [
                "Accept-Language": Locale.current.languageCode
            ]
        )
        
        networkLoader.loadData(with: request, timeout: timeout, completion: callback)
    }
    
    internal func registerUserRequest(callback: @escaping (Result<PandaUser, Error>) -> Void) {
        let request = createRequest(
            path: "/v1/users",
            method: .post,
            body: PandaUserInfo()
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }

    func verifySubscriptionsRequest(
        user: PandaUser,
        receipt: String,
        screenId: String?,
        callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/itunes/verify/\(user.id)",
            method: .post,
            query: ["screen_id" : screenId ?? ""],
            httpBody: receipt.data(using: .utf8)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }

    func getBillingPlan(
        with pandaID: String,
        callback: @escaping (Result<BillingPlan, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/billing-plans/\(pandaID)",
            method: .get
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func verifyApplePayRequest(
        user: PandaUser,
        paymentData: Data,
        billingID: String,
        webAppId: String,
        callback: @escaping (Result<ApplePayResult, Error>) -> Void
    ) {
        let decoder = JSONDecoder()
        guard
            let paymentInfo = try? decoder.decode(ApplePayPaymentInfo.self, from: paymentData)
        else {
            callback(.failure(ApplePayVerificationError.init(message: "ApplePayPaymentInfo decoding failed")))
            return
        }
        let payment = ApplePayPayment(
            data: paymentInfo.data,
            ephemeralPublicKey: paymentInfo.header.ephemeralPublicKey,
            publicKeyHash: paymentInfo.header.publicKeyHash,
            transactionId: paymentInfo.header.transactionId,
            signature: paymentInfo.signature,
            version: paymentInfo.version,
            sandbox: isDebug,
            webAppId: webAppId,
            productId: billingID,
            userId: user.id
        )
        let request = createRequest(
            path: "/v1/solid/ios",
            method: .post,
            body: payment
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        pushToken: String,
        user: PandaUser,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo(pushNotificationToken: pushToken)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        appsFlyerId: String,
        user: PandaUser,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo(appsFlyerId: appsFlyerId)
        )
        networkLoader.loadData(with: request, timeout: nil,  completion: callback)
    }
    
    func updateUser(
        advertisementId: String,
        user: PandaUser,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo(idfa: advertisementId)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        user: PandaUser,
        with customUserId: String,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo(customUserId: customUserId)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        user: PandaUser,
        pandaFacebookId: PandaFacebookId,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo.body(forPandaFacebookId: pandaFacebookId)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        user: PandaUser,
        idfv: String,
        idfa: String,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo(idfa: idfa, idfv: idfv)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        user: PandaUser,
        capiConfig: CAPIConfig,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo.body(forCAPIConfig: capiConfig)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func updateUser(
        user: PandaUser,
        with userProperties: Set<PandaUserProperty>,
        callback: @escaping (Result<PandaUser, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .put,
            body: PandaUserInfo.body(forUserProperties: userProperties)
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
    
    func verifySubscriptions(
        user: PandaUser,
        receipt: String,
        source: PaymentSource?,
        retries: Int = 1,
        callback: @escaping (Result<ReceiptVerificationResult, Error>) -> Void
    ) {
        retry(retries, task: { (onComplete) in
            self.verifySubscriptionsRequest(user: user, receipt: receipt, screenId: source?.screenId, callback: onComplete)
        }, completion: callback)
    }
    
    func verifyApplePay(
        user: PandaUser,
        paymentData: Data,
        billingID: String,
        webAppId: String,
        retries: Int = 1,
        callback: @escaping (Result<ApplePayResult, Error>) -> Void
    ) {
        retry(retries, task: { completion in
            self.verifyApplePayRequest(user: user, paymentData: paymentData, billingID: billingID, webAppId: webAppId, callback: completion)
        }, completion: callback)

    }

    func registerUser(
        retries: Int = 2,
        callback: @escaping (Result<PandaUser, Error>
        ) -> Void) {
        retry(retries, task: { (onComplete) in
            self.registerUserRequest(callback: onComplete)
        }, completion: callback)
    }
    
    func getUser(
        user: PandaUser,
        callback: @escaping (Result<PandaUserInfo, Error>) -> Void
    ) {
        let request = createRequest(
            path: "/v1/users/\(user.id)",
            method: .get
        )
        networkLoader.loadData(with: request, timeout: nil, completion: callback)
    }
}

// MARK: - Retry
private extension NetworkClient {
    func retry<T>(
        _ attempts: Int,
        interval: DispatchTimeInterval = .seconds(0),
        task: @escaping (_ completion:@escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        task({ [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure(let error):
                guard attempts > 0 else {
                    completion(result)
                    return
                }
                pandaLog("retries left \(attempts) and error = \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    self?.retry(attempts - 1, interval: interval, task: task, completion: completion)
                }
            }
        })
    }
}
