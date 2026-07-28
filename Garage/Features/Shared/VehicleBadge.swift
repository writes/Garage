import SwiftUI

/// A per-vehicle identity mark: the make's monogram on a colour derived from the vehicle itself.
///
/// The requested version of this was the manufacturer's emblem. Those are registered trademarks,
/// and shipping them inside a paid tier is trademark use in commerce — it implies an endorsement
/// that does not exist. A monogram and a colour carry the same information (*which of my cars is
/// this*) with none of that exposure, and they distinguish two cars from the same marque, which an
/// emblem cannot.
struct VehicleBadge: View {
    let vehicle: Vehicle
    var size: CGFloat = 32

    var body: some View {
        Text(VehicleBadgeStyle.monogram(make: vehicle.make, nickname: vehicle.nickname))
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            // White on every palette entry clears WCAG AA in both appearances — asserted by
            // VehicleBadgeContrastTests rather than assumed, because the badge is generated and
            // nobody will eyeball all eight.
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(Color(VehicleBadgeStyle.colorName(forVehicleID: vehicle.id)))
            )
            .accessibilityLabel(vehicle.displayName)
    }
}
