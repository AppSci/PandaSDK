//
//  NetworkLoader.swift
//  Panda
//
//  Created by Kuts on 30.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation

protocol NetworkLoader {
    func loadData<T: Codable>(with requestRes: Result<URLRequest, Error>, completion: @escaping (Result<T, Error>) -> Void)
}

struct ApiError: Error {
    let statusCode: Int
    let message: String?
}

private struct ApiErrorMessage: Codable {
    let message: String
}

extension URLSession: NetworkLoader {
    func loadData<T: Codable>(with requestRes: Result<URLRequest, Error>, completion: @escaping (Result<T, Error>) -> Void) {
        let request: URLRequest
        switch requestRes {
        case .failure(let error):
            completion(.failure(error))
            return
        case .success(let value):
            request = value
        }
        self.dataTask(with: request) { (data, response, error) in
            guard let data = data, let response = response as? HTTPURLResponse else {
                completion(.failure(error ?? Errors.unknownNetworkError))
                return
            }
            let decoder = JSONDecoder()
            guard response.statusCode < 400 else {
                let message = try? decoder.decode(ApiErrorMessage.self, from: data)
                completion(.failure(ApiError(statusCode: response.statusCode, message: message?.message)))
                return
            }
            do {
                let model = try decoder.decode(T.self, from: data)
                completion(.success(model))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

}
