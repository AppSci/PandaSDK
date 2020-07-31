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
            return localizedPrice()
        }
        
        guard #available(iOS 12.2, *) else {
            print("Minimum iOS 12.2 required for offerID [\(offer)] at product [\(productIdentifier)]")
            return ""
        }
        
        guard let discount = discounts.first(where: {$0.identifier == offerID!}) else {
            print("Couldn't find [\(offer)] at [\(productIdentifier)]")
            return ""
        }
        
        return localizedDiscountPrice(discount: discount)
    }
    
    private func unitStringFrom(periodUnit : SKProduct.PeriodUnit) -> String {
        var unit = ""
        switch periodUnit {
        case .day:
            unit = "day"
        case .week:
            unit = "week"
        case .month:
            unit = "month"
        case .year:
            unit = "year"
        default:
            break
        }
        return unit
    }
    
    //MARK:- Screen extension methods
    
    func regularUnitString() -> String {
        
        guard let subscriptionPeriod = subscriptionPeriod else {
            return ""
        }
        let unit = unitStringFrom(periodUnit: subscriptionPeriod.unit)
        let unit_count = subscriptionPeriod.numberOfUnits
        
        if unit_count > 1 {
            return "\(unit_count) \(unit)s"
        } else {
            return unit
        }
    }
    
    func discountDurationString(discount: SKProductDiscount) -> String{
        let periods_count = discount.numberOfPeriods
        let unit = unitStringFrom(periodUnit: discount.subscriptionPeriod.unit)
        let unit_count = discount.subscriptionPeriod.numberOfUnits
        let totalUnits = periods_count * unit_count
        
        if totalUnits > 1 {
            return "\(totalUnits) \(unit)s"
        } else {
            return unit
        }
    }
    
    func discountUnitString(discount: SKProductDiscount) -> String{
        let unit = unitStringFrom(periodUnit: discount.subscriptionPeriod.unit)
        let unit_count = discount.subscriptionPeriod.numberOfUnits
        
        if unit_count > 1 {
            return "\(unit_count) \(unit)s"
        } else {
            return unit
        }
    }
    
    func localizedPrice() -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = priceLocale
        let priceString = numberFormatter.string(from: price)
        return priceString ?? ""
    }
    
    func localizedDiscountPrice(discount: SKProductDiscount) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = priceLocale
        let priceString = numberFormatter.string(from: discount.price)
        return priceString ?? ""
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
