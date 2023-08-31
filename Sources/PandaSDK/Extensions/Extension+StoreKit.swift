//
//  Extension+StoreKit.swift
//  PandaSDK
//
//  Created by Andrew Skrypnyk on 23.07.2020.
//

import Foundation
import StoreKit

extension Product.SubscriptionPeriod {
    var unitDescription: String {
        if #available(iOS 15.4, *) {
            return unit.localizedDescription
        } else {
            return unit.description(capitalizeFirstLetter: true, numberOfUnits: value)
        }
    }
}

extension Product.SubscriptionPeriod.Unit {
    func description(capitalizeFirstLetter: Bool = false, numberOfUnits: Int? = nil) -> String {
        let period: String = {
            switch self {
            case .day:
                return "day"
            case .week:
                return "week"
            case .month:
                return "month"
            case .year:
                return "year"
            @unknown default:
                return ""
            }
        }()
        
        var numUnits = ""
        var plural = ""
        if let numberOfUnits = numberOfUnits {
            numUnits = "\(numberOfUnits) " /// Add space for formatting
            plural = numberOfUnits > 1 ? "s" : ""
        }
        return "\(numUnits)\(capitalizeFirstLetter ? period.capitalized : period)\(plural)"
    }
}
