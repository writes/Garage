import SwiftUI

/// A secondary line under a wear bar: something the bar itself cannot say.
///
/// `spoken` exists because the displayed text is written for the eye — "≈ 4,200 mi" — and VoiceOver
/// reads that as "almost equal to four thousand two hundred m i". The two strings say the same
/// thing; only one of them is pronounceable.
struct WearItemNote: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let spoken: String

    /// The projection. Approximate on its face on purpose: the figure is already rounded to two
    /// significant figures (`WearProjection`), and "at current rate" names the assumption the whole
    /// number rests on — that the owner keeps driving the way they have been.
    static func projection(milesToReplacement miles: Int) -> WearItemNote {
        WearItemNote(
            id: "projection",
            text: "≈ \(miles.formatted()) mi left at current rate",
            spoken: "About \(miles.formatted()) miles left at the current rate"
        )
    }

    /// Rubber ages whether or not it is used, and the wear percentage above says nothing about it.
    /// One decimal place: the install date is exact, so "5.2 years" is a figure the app can stand
    /// behind, unlike the projection above.
    static func tireAge(years: Double) -> WearItemNote {
        let figure = years.formatted(.number.precision(.fractionLength(1)))
        return WearItemNote(
            id: "tireAge",
            text: "Installed \(figure) years ago — rubber ages even with tread left.",
            spoken: "Installed \(figure) years ago. Rubber ages even with tread left."
        )
    }
}

struct WearItemBar: View {
    let label: String
    let percentage: Double
    let rawValue: String?
    /// Defaulted so the existing call sites and previews stay unchanged. Empty is the common case —
    /// every note here is derived, and derived means frequently unavailable.
    var notes: [WearItemNote] = []

    private var color: Color {
        if percentage > 60 { return Theme.Colors.wearGood }
        if percentage > 30 { return Theme.Colors.wearFair }
        return Theme.Colors.wearLow
    }

    /// Non-color signal for the wear health, also used as the VoiceOver value (WCAG 1.4.1).
    private var statusText: String {
        if percentage > 60 { return "Good" }
        if percentage > 30 { return "Fair" }
        return "Replace soon"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.caption)
                Spacer(minLength: Theme.Spacing.sm)
                if let rawValue {
                    Text(rawValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Text("\(Int(percentage))%")
                    .foregroundStyle(color)
                    .font(Theme.Typography.caption.weight(.semibold))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.secondary.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(max(percentage / 100, 0), 1))
                }
            }
            .frame(height: 8)
            // Secondary, never colored to the wear scale: these are context, not a verdict. An
            // amber "installed 6.1 years ago" would compete with the bar that is the actual health
            // reading.
            ForEach(notes) { note in
                Text(note.text)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        let parts = ["\(Int(percentage)) percent, \(statusText)"]
            + [rawValue].compactMap { $0 }
            + notes.map(\.spoken)
        return parts.joined(separator: ", ")
    }
}
