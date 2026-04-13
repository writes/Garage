import Foundation

enum Validators {
    static func nonEmpty(_ value: String, fieldName: String) -> AppError? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .validation("\(fieldName) is required.")
            : nil
    }

    static func positiveInteger(_ value: String, fieldName: String) -> AppError? {
        guard let number = Int(value), number > 0 else {
            return .validation("\(fieldName) must be greater than zero.")
        }
        return nil
    }

    static func odometer(_ value: String, lastKnown: Int?) -> AppError? {
        if let error = positiveInteger(value, fieldName: "Odometer") {
            return error
        }

        guard let number = Int(value) else {
            return .validation("Odometer must be a whole number.")
        }

        if let lastKnown, number < lastKnown {
            return .validation("Odometer must be at least \(lastKnown.formatted()).")
        }

        return nil
    }
}
