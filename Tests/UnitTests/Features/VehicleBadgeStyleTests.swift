import Foundation
import Testing
import UIKit
@testable import Garage

/// The badge is generated, so nobody will ever eyeball all eight colours or notice a car quietly
/// changing identity between launches. These assert both.
@MainActor
struct VehicleBadgeStyleTests {
    // MARK: - Stability

    /// The load-bearing property. `hashValue` could not be used here: Swift seeds its hasher per
    /// process, so the same id hashes differently after a relaunch and every car would silently
    /// change colour. FNV-1a is fully specified, so this expectation is meaningful across runs.
    @Test func theSameVehicleAlwaysGetsTheSameColour() {
        let id = "vehicle-9f2c"
        let first = VehicleBadgeStyle.colorName(forVehicleID: id)
        for _ in 0..<50 {
            #expect(VehicleBadgeStyle.colorName(forVehicleID: id) == first)
        }
    }

    @Test func theHashIsTheDocumentedFNV1aValue() {
        // Pinned against the reference algorithm: if someone swaps the hash for something
        // "equivalent", every existing user's cars change colour and this test says so.
        #expect(VehicleBadgeStyle.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(VehicleBadgeStyle.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func differentVehiclesSpreadAcrossThePalette() {
        let names = (0..<200).map { VehicleBadgeStyle.colorName(forVehicleID: "vehicle-\($0)") }
        // Not a distribution test — just that it is not collapsing onto one entry.
        #expect(Set(names).count >= VehicleBadgeStyle.palette.count - 1)
    }

    @Test func everyColourNameComesFromThePalette() {
        for index in 0..<100 {
            #expect(VehicleBadgeStyle.palette.contains(VehicleBadgeStyle.colorName(forVehicleID: "vehicle-\(index)")))
        }
    }

    /// An id can be empty for a vehicle mid-creation, and `% 0` would trap.
    @Test func anEmptyIdStillResolvesToAColour() {
        #expect(VehicleBadgeStyle.palette.contains(VehicleBadgeStyle.colorName(forVehicleID: "")))
    }

    // MARK: - Monogram

    @Test func theMonogramComesFromTheMake() {
        #expect(VehicleBadgeStyle.monogram(make: "Porsche", nickname: "Weekend car") == "P")
    }

    /// "LR" reads as a mark; "LA" for Land Rover would read as a typo.
    @Test func aTwoWordMakeContributesAnInitialEach() {
        #expect(VehicleBadgeStyle.monogram(make: "Land Rover", nickname: "") == "LR")
        #expect(VehicleBadgeStyle.monogram(make: "Alfa Romeo", nickname: "") == "AR")
    }

    /// The nickname is the fallback source, and the SAME two-word rule applies to it — "Track toy"
    /// is "TT" for the same reason "Land Rover" is "LR". The rule is about the words, not about
    /// which field they came from.
    @Test func theNicknameIsUsedWhenTheMakeIsBlank() {
        #expect(VehicleBadgeStyle.monogram(make: "   ", nickname: "Track toy") == "TT")
        #expect(VehicleBadgeStyle.monogram(make: "   ", nickname: "Viper") == "V")
    }

    @Test func nothingUsableStillRendersSomething() {
        #expect(VehicleBadgeStyle.monogram(make: "", nickname: "") == "?")
    }

    @Test func theMonogramIsUppercased() {
        #expect(VehicleBadgeStyle.monogram(make: "porsche", nickname: "") == "P")
    }
}

/// White text sits on every badge, so every badge must clear WCAG AA in BOTH appearances. Resolves
/// the COMPILED asset catalog rather than the source hex, so a bad edit to a colorset is caught.
@MainActor
struct VehicleBadgeContrastTests {
    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> Double {
            let raw = Double(value)
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrastWithWhite(_ color: UIColor) -> Double {
        let lighter = max(luminance(color), 1.0)
        let darker = min(luminance(color), 1.0)
        return (lighter + 0.05) / (darker + 0.05)
    }

    @Test func everyBadgeColourCarriesWhiteTextAtAAInBothAppearances() {
        for name in VehicleBadgeStyle.palette {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let traits = UITraitCollection(userInterfaceStyle: style)
                guard let color = UIColor(named: name, in: .main, compatibleWith: traits) else {
                    Issue.record("Missing colorset \(name)")
                    continue
                }
                let ratio = contrastWithWhite(color.resolvedColor(with: traits))
                #expect(ratio >= 4.5, "\(name) in \(style == .light ? "light" : "dark") is \(ratio):1")
            }
        }
    }
}
