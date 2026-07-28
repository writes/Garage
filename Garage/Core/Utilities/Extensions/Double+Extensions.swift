import Foundation

extension Double {
    var currencyText: String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    var mpgText: String {
        self.formatted(.number.precision(.fractionLength(1))) + " MPG"
    }

    /// Cost per mile lands in cents, so the two-decimal currency format rounds most real values to
    /// "$0.00" or "$1.00" — three decimals is what makes the figure say anything at all.
    var currencyPerMileText: String {
        "$" + self.formatted(.number.precision(.fractionLength(3))) + "/mi"
    }
}
