import Foundation

extension Double {
    var currencyText: String {
        Formatters.currency.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    var mpgText: String {
        self.formatted(.number.precision(.fractionLength(1))) + " MPG"
    }
}
