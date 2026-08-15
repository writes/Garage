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

/// The corners a chamfer cuts. The adopted concept's card geometry cuts exactly ONE corner —
/// the top right (`clip-path: polygon(0 0, calc(100% - 18px) 0, 100% 18px, 100% 100%, 0 100%)`,
/// underhood concept CSS) — so `.topRight` is the DEFAULT: the hook's resting state must be able
/// to reproduce the frozen design without a call-site opt-in (tri-review finding). `.all` stays
/// expressible for a future pack that wants the symmetric cut.
struct DesignCornerSet: OptionSet, Equatable, Sendable {
    let rawValue: Int

    static let topLeft = DesignCornerSet(rawValue: 1 << 0)
    static let topRight = DesignCornerSet(rawValue: 1 << 1)
    static let bottomLeft = DesignCornerSet(rawValue: 1 << 2)
    static let bottomRight = DesignCornerSet(rawValue: 1 << 3)
    static let all: DesignCornerSet = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

/// Corner geometry for one component class. `chamfer` is the concept-geometry hook: 0 — control
/// everywhere — is exactly the `RoundedRectangle(cornerRadius:)` every surface clips to today; a
/// positive value CUTS the named corners instead of rounding them.
struct DesignCorner: Equatable, Sendable {
    let radius: CGFloat
    let chamfer: CGFloat
    let chamferedCorners: DesignCornerSet

    init(radius: CGFloat, chamfer: CGFloat = 0, chamferedCorners: DesignCornerSet = .topRight) {
        self.radius = radius
        self.chamfer = chamfer
        self.chamferedCorners = chamferedCorners
    }

    var isChamfered: Bool { chamfer > 0 }

    /// The shape to clip or stroke with. Type-erased because the two branches are different
    /// `Shape` types; the un-chamfered branch renders identically to the literal
    /// `RoundedRectangle` it replaced.
    var shape: AnyShape {
        isChamfered
            ? AnyShape(ChamferedRectangle(chamfer: chamfer, corners: chamferedCorners))
            : AnyShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// A rectangle whose named corners are cut rather than rounded. Unused by control — it exists so
/// the `chamfer` token is a real hook and not a field nothing can honour. With `corners:
/// .topRight` (the default) and an 18pt cut this is point-for-point the concept's card
/// `clip-path: polygon(0 0, calc(100% - 18px) 0, 100% 18px, 100% 100%, 0 100%)`.
struct ChamferedRectangle: Shape {
    let chamfer: CGFloat
    var corners: DesignCornerSet = .topRight

    func path(in rect: CGRect) -> Path {
        // Clamped so an oversized chamfer degrades to a diamond instead of self-intersecting.
        let cut = max(0, min(chamfer, min(rect.width, rect.height) / 2))
        let topLeft = corners.contains(.topLeft) ? cut : 0
        let topRight = corners.contains(.topRight) ? cut : 0
        let bottomRight = corners.contains(.bottomRight) ? cut : 0
        let bottomLeft = corners.contains(.bottomLeft) ? cut : 0
        // An un-cut corner contributes coincident points, which a Path renders as the square
        // corner itself — one code path serves every combination.
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + topRight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addLine(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.closeSubpath()
        return path
    }
}
