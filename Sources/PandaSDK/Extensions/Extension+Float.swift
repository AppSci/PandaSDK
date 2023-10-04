//
//  File.swift
//  
//
//  Created by Yegor Kyrylov on 08.09.2022.
//

import Foundation

public extension Float {
    /// Returns rounded number that will have 1 or 2 digits after the dot. Example: 13.21
    ///
    /// - Returns: maths rounded number to hundredths
    func roundedToHundredths() -> Float {
        return Float((100 * self).rounded() / 100)
    }
}

public struct MonetaryAmount: Equatable {
    public let amountCents: Int
    public let amountDollars: Float

    public init(amountCents: Int) {
        self.init(amountDollars: Float(amountCents) / 100)
    }

    public init(amountDollars: Float) {
        let adjustedAmount = amountDollars.roundedToHundredths()
        self.amountCents = Int((adjustedAmount * 100).rounded())
        self.amountDollars = adjustedAmount
    }
}
