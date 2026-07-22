import SwiftUI

/// The curated set of Pro accent themes (Phase-1 in-Pro theming A/B). Deliberately a fixed, small
/// list — NOT a theme engine (no color wheel, no per-vehicle palettes, no user-authored colors).
/// Every tint is dark/saturated enough to carry white foreground text at WCAG-AA in BOTH light and
/// dark appearances (the tints are fixed Colors, so they render identically in each). `.classic`
/// maps to the existing BrandPrimary asset so default and free users stay pixel-identical to today.
enum AccentScheme: String, CaseIterable, Identifiable, Sendable {
    case classic
    case graphite
    case marine
    case plum

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .classic: return Color("BrandPrimary")
        case .graphite: return Color(red: 0.22, green: 0.25, blue: 0.31)
        case .marine: return Color(red: 0.05, green: 0.35, blue: 0.55)
        case .plum: return Color(red: 0.42, green: 0.20, blue: 0.50)
        }
    }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .graphite: return "Graphite"
        case .marine: return "Marine"
        case .plum: return "Plum"
        }
    }
}

/// The single live source of truth for the app accent. Reading `scheme` inside a SwiftUI body
/// registers an Observation dependency, so changing it live-recolors every accent surface with no
/// relaunch. Persistence + the Pro gate live in ProfileViewModel; this only holds the live value.
@MainActor
@Observable
final class AccentStore {
    static let shared = AccentStore()

    var scheme: AccentScheme = .classic

    private init() {}

    /// Maps a persisted theme id to a scheme; nil / empty / unrecognized gracefully downgrade to
    /// `.classic`, so a bad or missing value can never break the UI or leak across accounts.
    func apply(themeID: String?) {
        scheme = themeID.flatMap(AccentScheme.init(rawValue:)) ?? .classic
    }
}
