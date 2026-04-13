import Foundation

extension Date {
    var shortDisplay: String {
        Formatters.shortDate.string(from: self)
    }
}
