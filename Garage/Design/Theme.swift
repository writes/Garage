import SwiftUI

enum Theme {
    enum Colors {
        static let primary = Color("BrandPrimary")
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
