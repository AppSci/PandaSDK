//
//  Extension+Data.swift
//  
//
//  Created by Denys Danyliuk on 12.09.2023.
//

import Foundation

extension Data {
    func hexString() -> String {
        reduce("") { result, element in
            result + String(format: "%02.2hhx", element)
        }
    }
}
