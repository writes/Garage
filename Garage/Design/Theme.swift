import SwiftUI

enum Theme {
    enum Colors {
        // `primary` is the one themeable accent (Phase-1 in-Pro theming). Reading it inside a
        // SwiftUI body registers an Observation dependency on AccentStore.shared.scheme, so
        // changing the scheme live-recolors every accent surface with no relaunch. It reads the
        // singleton deliberately — a `static` cannot read @Environment — and is @MainActor because
        // the store is. Only reads inside a SwiftUI body are reactive: do not cache this in a
        // stored `let`/init or bridge it to UIColor and expect updates. All other tokens stay
        // `static let`. Default (`.classic`) resolves to Color("BrandPrimary"), unchanged.
        @MainActor static var primary: Color { AccentStore.shared.scheme.tint }
        static let secondary = Color("BrandSecondary")
        static let accent = Color("Accent")
        static let background = Color("Background")
        static let surface = Color("Surface")
        static let textPrimary = Color("TextPrimary")
        static let textSecondary = Color("TextSecondary")
        static let error = Color("Error")
        static let success = Color("Success")
        static let warning = Color("Warning")
        static let wearGood = Color("Success")
        static let wearFair = Color("Warning")
        static let wearLow = Color("Error")
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title2, design: .rounded, weight: .semibold)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .default, weight: .regular)
        static let caption = Font.system(.caption, design: .default, weight: .regular)
        static let mono = Font.system(.body, design: .monospaced, weight: .medium)
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let full: CGFloat = 999
    }
}
