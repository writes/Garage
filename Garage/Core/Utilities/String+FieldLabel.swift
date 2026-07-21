import Foundation

extension String {
    /// Converts a camelCase or snake_case storage key (e.g. "bestLapTime", "pad_compound")
    /// into a human-readable field label (e.g. "Best Lap Time", "Pad Compound") for display.
    /// Storage keys are DB values, never meant to be shown to the user verbatim.
    var humanizedFieldLabel: String {
        guard !isEmpty else { return self }
        var spaced = ""
        var previous: Character?
        for character in self {
            if character == "_" || character == "-" {
                if !spaced.isEmpty, !spaced.hasSuffix(" ") { spaced.append(" ") }
            } else {
                if let previous, !previous.isUppercase, character.isUppercase {
                    spaced.append(" ")
                }
                spaced.append(character)
            }
            previous = character
        }
        return spaced
            .split(separator: " ")
            .map { word in word.prefix(1).uppercased() + word.dropFirst() }
            .joined(separator: " ")
    }
}

extension RawRepresentable where RawValue == String {
    /// A user-facing label for a string-backed enum case, derived from the CASE NAME rather than the
    /// raw storage value (often an abbreviated/snake_case code like "fl" or "paint_correction" that
    /// must never be shown to users). Enums needing special formatting override this.
    var displayName: String { String(describing: self).humanizedFieldLabel }
}

extension FuelType {
    var displayName: String {
        switch self {
        case .regular87: "Regular 87"
        case .premium91: "Premium 91"
        case .premium93: "Premium 93"
        case .e85: "E85"
        case .diesel: "Diesel"
        }
    }
}

extension DetailingType {
    var displayName: String {
        self == .ppf ? "PPF" : String(describing: self).humanizedFieldLabel
    }
}
