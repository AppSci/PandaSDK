//
//  Extension+StoreKit.swift
//  PandaSDK
//
//  Created by Andrew Skrypnyk on 23.07.2020.
//

import Foundation
import StoreKit

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
}
