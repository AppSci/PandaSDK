//
//  String+StoreKit.swift
//  NVActivityIndicatorView
//
//  Created by Kuts on 03.08.2020.
//

import Foundation
import StoreKit

extension String {
    
    mutating func updatedProductInfo(product: SKProduct) -> String {
        let info = product.productInfoDictionary()
        
        let title = info["title"] ?? ""
        self = replacingOccurrences(of: "{{product_title}}", with: title)
        
        let productIdentifier = info["productIdentifier"] ?? ""
        self = replacingOccurrences(of: "{{product_id}}", with: productIdentifier)
        
        let tryString = info["tryString"] ?? ""
        self = replacingOccurrences(of: "{{introductionary_information}}", with: tryString)
        
        let thenString = info["thenString"] ?? ""
        self = replacingOccurrences(of: "{{product_pricing_terms}}", with: thenString)
        
        return self
    }
    
    func updatedTrialDuration(product: SKProduct) -> String {
        if let introductoryDiscount = product.introductoryPrice {
            let introPrice = product.discountDurationString(discount: introductoryDiscount)
            let macros = "{{trial_duration:\(product.productIdentifier)}}"
            return replacingOccurrences(of: macros, with: introPrice)
        }
        return self
    }
    
    func updatedProductPrice(product: SKProduct) -> String {
        let replace_string = product.localizedString()
        let macros = "{{product_price:\(product.productIdentifier)}}"
        return replacingOccurrences(of: macros, with: replace_string)
    }
    
    func updatedProductDuration(product: SKProduct) -> String {
        let replace_string = product.regularUnitString()
        let macros = "{{product_duration:\(product.productIdentifier)}}"
        return replacingOccurrences(of: macros, with: replace_string)
    }
    
    func updatedProductIntroductoryPrice(product: SKProduct) -> String {
        if let introductoryPrice = product.introductoryPrice {
            let introPrice = product.localizedDiscountPriceString(discount: introductoryPrice)
            let macros = "{{offer_price:\(product.productIdentifier)}}"
            return replacingOccurrences(of: macros, with: introPrice)
        }
        return self
    }
    
    func updatedProductIntroductoryDuration(product: SKProduct) -> String {
        if let introductoryDiscount = product.introductoryPrice {
            let introPrice = product.discountDurationString(discount: introductoryDiscount)
            let macros = "{{offer_duration:\(product.productIdentifier)}}"
            return replacingOccurrences(of: macros, with: introPrice)
        }
        return self
    }
}
