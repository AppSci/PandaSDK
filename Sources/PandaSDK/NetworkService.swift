//
//  NetworkService.swift
//  Panda
//
//  Created by Kuts on 30.06.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation

class NetworkService {
    ///Used to set a`URLRequest`'s HTTP Method
    enum HttpMethod: String {
        case get = "GET"
        case patch = "PATCH"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
    }
    ///used to switch between live and Mock Data
    var dataLoader: NetworkLoader
  
    init(dataLoader: NetworkLoader = URLSession.shared) {
      self.dataLoader = dataLoader
    }
    
    func createRequest(url: URL?, method: HttpMethod = .get) -> URLRequest? {
        
        guard let requestUrl = url else {
            print("request URL is nil")
            return nil
        }

        var request = URLRequest(url: requestUrl)
        request.httpMethod = method.rawValue

        return request
    }
}
