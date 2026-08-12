import SwiftUI

/// A colour token held as DATA rather than as an opaque `Color`, so a pack's palette can be
/// pinned by a test and diffed between arms. `asset` names an asset colorset — the shipped
/// design, whose colorsets carry both a light and a dark variant; `srgb` carries a literal, which
/// is how a concept's CSS custom properties arrive.
enum DesignColor: Equatable, Sendable {
    case asset(String)
    case srgb(red: Double, green: Double, blue: Double, opacity: Double)

    var color: Color {
        switch self {
        case .asset(let name):
            return Color(name)
        case .srgb(let red, let green, let blue, let opacity):
            return Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
        }
    }
}

/// Every semantic colour role in the app. `Theme.Colors` reads nothing else, so a pack repaints
/// all 137 colour call sites without one of them being edited.
struct DesignColors: Equatable, Sendable {
    /// The accent this pack ships with. It is the pack's DEFAULT, not a replacement: an accent the
    /// user explicitly picked in Pro theming still wins inside whatever pack is active (arm
    /// manifest §1, last row). See `Theme.Colors.primary` for the composition rule.
    let accentDefault: DesignColor
    /// Foreground for content sitting ON an `accentDefault`/`primary` fill.
    let onPrimary: DesignColor
    let secondary: DesignColor
    let accent: DesignColor
    let background: DesignColor
    let surface: DesignColor
    let textPrimary: DesignColor
    let textSecondary: DesignColor
    let error: DesignColor
    let success: DesignColor
    let warning: DesignColor
    let wearGood: DesignColor
    let wearFair: DesignColor
    let wearLow: DesignColor
    /// Card/button elevation. Alpha lives in the token, so call sites must not add `.opacity()`.
    let shadow: DesignColor
}

/// One step of a type ramp, held as size + design + weight rather than as a built `Font` — a
/// `Font` cannot be inspected, so only this shape can be pinned by the control token test.
struct DesignFont: Equatable, Sendable {
    /// Dynamic-type native (the shipped ramp) or a fixed point size, which is how a concept's
    /// display/label ramp is specified.
    enum Scale: Equatable, Sendable {
        case textStyle(Font.TextStyle)
        case fixed(CGFloat)
    }

    let scale: Scale
    let design: Font.Design
    let weight: Font.Weight

    var font: Font {
        switch scale {
        case .textStyle(let style):
            return .system(style, design: design, weight: weight)
        case .fixed(let size):
            return .system(size: size, weight: weight, design: design)
        }
    }
}

/// The type ramp.
struct DesignTypography: Equatable, Sendable {
    let largeTitle: DesignFont
    let title: DesignFont
    let headline: DesignFont
    let body: DesignFont
    let caption: DesignFont
    let mono: DesignFont
}

/// The spacing scale.
struct DesignSpacing: Equatable, Sendable {
    let xxs: CGFloat
    let xs: CGFloat
    let sm: CGFloat
    let md: CGFloat
    let lg: CGFloat
    let xl: CGFloat
    let xxl: CGFloat
}

/// The corner-radius scale.
struct DesignRadius: Equatable, Sendable {
    let sm: CGFloat
    let md: CGFloat
    let lg: CGFloat
    let full: CGFloat
}

/// Corner geometry for one component class. `chamfer` is the concept-geometry hook: 0 — control
/// everywhere — is exactly the `RoundedRectangle(cornerRadius:)` every surface clips to today; a
/// positive value CUTS the corner instead of rounding it.
struct DesignCorner: Equatable, Sendable {
    let radius: CGFloat
    let chamfer: CGFloat

    init(radius: CGFloat, chamfer: CGFloat = 0) {
        self.radius = radius
        self.chamfer = chamfer
    }

    var isChamfered: Bool { chamfer > 0 }

    /// The shape to clip or stroke with. Type-erased because the two branches are different
    /// `Shape` types; the un-chamfered branch renders identically to the literal
    /// `RoundedRectangle` it replaced.
    var shape: AnyShape {
        isChamfered
            ? AnyShape(ChamferedRectangle(chamfer: chamfer))
            : AnyShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// A rectangle whose corners are cut rather than rounded. Unused by control — it exists so the
/// `chamfer` token is a real hook and not a field nothing can honour.
struct ChamferedRectangle: Shape {
    let chamfer: CGFloat

    func path(in rect: CGRect) -> Path {
        // Clamped so an oversized chamfer degrades to a diamond instead of self-intersecting.
        let cut = max(0, min(chamfer, min(rect.width, rect.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        path.closeSubpath()
        return path
    }
}
