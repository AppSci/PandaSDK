//
//  Errors.swift
//  Panda
//
//  Created by Kuts on 02.07.2020.
//  Copyright © 2020 Kuts. All rights reserved.
//

import Foundation

enum Errors: Error {
    case message(String)
    case notConfigured
    
    case appStoreReceiptError(Error)
    case invalidProductId(String)
    case unknownStoreError
}
