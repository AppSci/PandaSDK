//
//  File.swift
//  
//
//  Created by Yegor Kyrylov on 07.09.2022.
//

import Foundation

struct BillingPlan: Codable {
    let id: String?
    let countryCode: String?
    let productID: String?
    let currency: String?
    let amount: Int?
    let firstPayment: Int?
    let secondPayment: Int?
    let paymentMode: String?
    let subscriptionType: String?
    let trialDescription: String?
    let billingPeriod: String?
    let billingPeriodInDays: Int?
    let orderDescription: String?
    let hasTrial: Bool?
    let durationTrialInDays: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case billingPeriod = "billing_period"
        case billingPeriodInDays = "billing_period_in_days"
        case currency
        case durationTrialInDays = "duration_trial_in_days"
        case firstPayment = "first_payment"
        case hasTrial = "has_trial"
        case orderDescription = "order_description"
        case paymentMode = "payment_mode"
        case productID = "product_id"
        case secondPayment = "second_payment"
        case subscriptionType = "subscription_type"
        case trialDescription = "trial_description"
        case countryCode = "country_code"
    }

    func getPrice() -> String {
        guard
            let price = firstPayment
        else {
            return "0"
        }

        return MonetaryAmount(amountCents: price).amountDollars.description
    }

    func getLabelForApplePayment() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"

        var text = ""

        if let trial = hasTrial {

            if let trialDaysDuration = durationTrialInDays,
               trial {
                text.append("FREE WEEK WITH 1 LESSON, ")

                if let secondPayment = secondPayment {

                    let currentDate = Date()
                    var dateComponent = DateComponents()
                    dateComponent.day = trialDaysDuration

                    if let futureDate = Calendar.current.date(byAdding: dateComponent, to: currentDate) {

                        text.append("\(MonetaryAmount(amountCents: secondPayment).amountDollars.description)")

                        if let currency = currency {
                            let currencySymbol = CurrencyHelper.getSymbolForCurrencyCode(code: currency)

                            if !currencySymbol.isEmpty {
                                text.append("\(currencySymbol)/MONTH")
                            }
                        }

                        text.append(" FROM \(dateFormatter.string(from: futureDate))")
                    }
                }
            } else {
                text.append(subscriptionType ?? "")
            }
        } else {
            text.append(subscriptionType ?? "")
        }

        return text
    }
}
