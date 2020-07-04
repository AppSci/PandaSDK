//
//  WeakObject.swift
//  PandaSDK
//
//  Created by Kuts on 04.07.2020.
//

import Foundation

struct WeakObject<T: AnyObject> {
    
    private(set) weak var value: T?
    init(value: T) {
        self.value = value
    }

}

extension WeakObject: Equatable where T: Equatable {
}

extension WeakObject: Hashable where T: Hashable {
}

