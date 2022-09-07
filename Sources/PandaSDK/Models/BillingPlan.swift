//
//  File.swift
//  
//
//  Created by Yegor Kyrylov on 07.09.2022.
//

struct BillingPlan: Codable {
    let id: ID<BillingPlan>
    let amount: Int
    let billingPeriod: String
    let billingPeriodInDays: Int
    let currency: String
    let durationTrial: String
    let durationTrialInDays: Int
    let firstPayment: Int
    let hasTrial: Bool
    let orderDescription: String
    let paymentMode: String
    let productID: String
    let secondPayment: Int
    let subscriptionType: String
    let trialDescription: String

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case billingPeriod = "billing_period"
        case billingPeriodInDays = "billing_period_in_days"
        case currency
        case durationTrial = "duration_trial"
        case durationTrialInDays = "duration_trial_in_days"
        case firstPayment = "first_payment"
        case hasTrial = "has_trial"
        case orderDescription = "order_description"
        case paymentMode = "payment_mode"
        case productID = "product_id"
        case secondPayment = "second_payment"
        case subscriptionType = "subscription_type"
        case trialDescription = "trial_description"
    }
}
