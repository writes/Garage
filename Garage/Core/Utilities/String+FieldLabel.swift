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
