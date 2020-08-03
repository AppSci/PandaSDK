//
//  Extension+StoreKit.swift
//  PandaSDK
//
//  Created by Andrew Skrypnyk on 23.07.2020.
//

import Foundation
import StoreKit


extension SKProduct.PeriodUnit {
    func description(capitalizeFirstLetter: Bool = false, numberOfUnits: Int? = nil) -> String {
        let period:String = {
            switch self {
            case .day: return "day"
            case .week: return "week"
            case .month: return "month"
            case .year: return "year"
            @unknown default: return ""
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

extension SKProduct {
    
    func localizedString(with offerID : String? = nil) -> String {
        
        guard let offer = offerID else {
            return localizedPriceString()
        }
        
        guard #available(iOS 12.2, *) else {
            print("Minimum iOS 12.2 required for offerID [\(offer)] at product [\(productIdentifier)]")
            return ""
        }
        
        guard let discount = discounts.first(where: {$0.identifier == offerID!}) else {
            print("Couldn't find [\(offer)] at [\(productIdentifier)]")
            return ""
        }
        
        return localizedDiscountPriceString(discount: discount)
    }
    
    private func unitStringFrom(periodUnit : SKProduct.PeriodUnit) -> String {
        switch periodUnit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        default: return ""
        }
    }
    
    //MARK: - Screen extension methods
    
    func regularUnitString() -> String {
        guard let subscriptionPeriod = subscriptionPeriod else {
            return ""
        }
        let unitString = unitStringFrom(periodUnit: subscriptionPeriod.unit)
        let numberOfUnits = subscriptionPeriod.numberOfUnits
        return numberOfUnits > 1 ? "\(numberOfUnits) \(unitString)s" : unitString
    }
    
    func discountDurationString(discount: SKProductDiscount) -> String {
        let periodsNumber = discount.numberOfPeriods
        let unitString = unitStringFrom(periodUnit: discount.subscriptionPeriod.unit)
        let unitsNumber = discount.subscriptionPeriod.numberOfUnits
        let totalUnits = periodsNumber * unitsNumber
        return totalUnits > 1 ? "\(totalUnits) \(unitString)s" : unitString
    }
    
    func discountUnitString(discount: SKProductDiscount) -> String {
        let unitString = unitStringFrom(periodUnit: discount.subscriptionPeriod.unit)
        let unitsNumber = discount.subscriptionPeriod.numberOfUnits
        return unitsNumber > 1 ? "\(unitsNumber) \(unitString)s" : unitString
    }
    
    func localizedPriceString() -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = priceLocale
        let stringFromPrice = numberFormatter.string(from: price)
        return stringFromPrice ?? ""
    }
    
    func localizedDiscountPriceString(discount: SKProductDiscount) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = priceLocale
        let stringFromPrice = numberFormatter.string(from: discount.price)
        return stringFromPrice ?? ""
    }
    
    func productInfoDictionary() -> [String: String] {
        
        var tryString = ""
        var thenString = ""
        let title = localizedTitle
        
        if #available(iOS 12.2, *) {
            if let offer = introductoryPrice {
                let isTrial = offer.paymentMode == .freeTrial

                var symbol = "$"
                let paymentValue = offer.price
                let period = offer.subscriptionPeriod
                
                // due to Apple Bug: http://www.openradar.me/37391667
                if offer.priceLocale != nil,
                    let currencySymbol = offer.priceLocale.currencySymbol {
                    symbol = currencySymbol
                }
                
                let trialPeriod = period.unit.description(capitalizeFirstLetter: true, numberOfUnits: period.numberOfUnits)
                tryString = "Try \(trialPeriod) for \(isTrial ? "Free" : "\(symbol) \(paymentValue)")."
            }
        }
        
        var symbol = "$"
        /// due to Apple Bug: http://www.openradar.me/37391667
        if priceLocale != nil,
            let currencySymbol = priceLocale.currencySymbol {
            symbol = currencySymbol
        }
        
        /// I guessed, that for consumable and non-cunsumable subscriptions,
        /// `subscriptionPeriod` should be nil, but I was wrong (any documentation about that).
        /// According to docs: This read-only property is nil if the product is not a subscription.
        /// That's why I check subsPeriod for 0 days.
        if let subsPeriod = subscriptionPeriod {
            
            let periodNumber = subsPeriod.numberOfUnits
            if periodNumber == 0 && subsPeriod.unit == .day {
                /// set string for Lifetime
                thenString = "for \(symbol) \(price) lifetime"
            } else {
                /// set thenString for subscription
                let periodString = subsPeriod.unit.description(capitalizeFirstLetter: true, numberOfUnits: periodNumber)
                thenString = "then \(symbol) \(price) per \(periodString)"
            }
        
        } else {
            /// set string for Lifetime
            thenString = "for \(symbol) \(price) lifetime"
        }
        
        var result: [String: String] = [:]

        result["productIdentifier"] = productIdentifier

        if !title.trimmingCharacters(in: .whitespaces).isEmpty {
            result["title"] = title
        }
        if !tryString.trimmingCharacters(in: .whitespaces).isEmpty {
            result["tryString"] = tryString
        }
        if !thenString.trimmingCharacters(in: .whitespaces).isEmpty {
            result["thenString"] = thenString
        }
        
        return result
    }
}
