import SwiftUI

extension Color {
    /// Card/button drop shadow. An asset colorset rather than a literal because a black shadow at
    /// 8% is effectively invisible against a near-black dark-mode background — the dark variant
    /// carries the same hue at 50% so elevation still reads. Alpha lives in the colorset, so call
    /// sites must not add their own `.opacity()`.
    ///
    /// Routed through the active pack like every other colour role, so a pack that repaints
    /// elevation reaches all three shadow call sites without touching one of them.
    @MainActor static var garageShadow: Color { Theme.Colors.shadow }
}
