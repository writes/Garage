import SwiftUI

extension Color {
    /// Card/button drop shadow. An asset colorset rather than a literal because a black shadow at
    /// 8% is effectively invisible against a near-black dark-mode background — the dark variant
    /// carries the same hue at 50% so elevation still reads. Alpha lives in the colorset, so call
    /// sites must not add their own `.opacity()`.
    static let garageShadow = Color("ShadowColor")
}
