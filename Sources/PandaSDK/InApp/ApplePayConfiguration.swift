//
//  ApplePayConfiguration.swift
//  
//
//  Created by Roman Mishchenko on 02.06.2022.
//

import Foundation

public struct ApplePayConfiguration {
    let merchantIdentifier: String

    public init(merchantIdentifier: String) {
        self.merchantIdentifier = merchantIdentifier
    }
}
