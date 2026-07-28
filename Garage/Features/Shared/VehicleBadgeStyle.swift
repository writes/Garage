import Foundation

/// A distinct visual identity per vehicle, derived from data the app already has.
///
/// ## Why not manufacturer emblems
///
/// The obvious version of this feature is the real badge — the roundel, the crest, the star. Those
/// are registered trademarks, and shipping them inside a paid tier is trademark use in commerce:
/// it implies an endorsement that does not exist, and it is the kind of thing that draws a
/// takedown rather than a warning. A monogram and a colour carry the same information — *which of
/// my cars is this* — with none of that exposure, and they do something emblems cannot: two BMWs
/// still look different from each other.
///
/// ## Stability is the whole point
///
/// The colour must be the same on every launch, on every device, forever. `hashValue` cannot be
/// used for this: Swift seeds its hasher per process, so the same string hashes differently after
/// a relaunch and every car would silently change colour. FNV-1a over the id's UTF-8 bytes is
/// fully specified and gives the same answer everywhere.
enum VehicleBadgeStyle {
    /// Eight hues, each dark enough to carry white text at WCAG AA. Ordered so that adjacent
    /// entries are visually distant — consecutive vehicles usually land on neighbouring indices,
    /// and two similar blues side by side would defeat the point.
    static let palette: [String] = [
        "BadgeSlate", "BadgeRust", "BadgeMoss", "BadgePlum",
        "BadgeMarine", "BadgeClay", "BadgeForest", "BadgeInk"
    ]

    /// FNV-1a, 64-bit. Chosen for being fully specified rather than for speed: the requirement is
    /// that this returns the same number on every platform and every launch.
    static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            // 0x100000001b3 — grouped 3+4+4, NOT 4+4+4. Written as 0x1000_0000_01b3 this is
            // twelve hex digits instead of eleven, a different multiplier entirely, and the hash
            // silently stops being FNV-1a while still looking deterministic. The pinned reference
            // values in VehicleBadgeStyleTests are what caught it.
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }

    static func colorName(forVehicleID id: String) -> String {
        // Empty id is reachable (a vehicle mid-creation), and `% 0` would trap — but the palette
        // is a compile-time constant, so the real guard is against someone emptying it later.
        guard !palette.isEmpty else { return "BadgeSlate" }
        return palette[Int(stableHash(id) % UInt64(palette.count))]
    }

    /// One or two letters, from the make. Two-word makes contribute an initial each ("Land Rover"
    /// → "LR"); everything else takes the first letter, because "ME" for Mercedes reads as a word
    /// rather than a mark.
    static func monogram(make: String, nickname: String) -> String {
        let source = make.trimmed.isEmpty ? nickname.trimmed : make.trimmed
        let words = source.split(separator: " ").filter { !$0.isEmpty }
        guard let first = words.first?.first else { return "?" }
        if words.count > 1, let second = words[1].first {
            return String([first, second]).uppercased()
        }
        return String(first).uppercased()
    }
}
