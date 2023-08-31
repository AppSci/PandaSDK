//
//  ScreenCache.swift
//  
//
//  Created by Denys Danyliuk on 06.09.2023.
//

import Foundation

final class ScreenCache {
    var cache: [String: ScreenData] = [:]
    
    subscript(screenID: String?) -> ScreenData? {
        get {
            guard let key = screenID else { return nil }
            return cache[key]
        }
        set {
            guard let key = screenID else { return }
            guard let newValue = newValue else {
                cache.removeValue(forKey: key)
                return
            }
            cache[key] = newValue
        }
    }
}
