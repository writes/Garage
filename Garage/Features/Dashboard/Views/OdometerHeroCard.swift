import SwiftUI

struct OdometerHeroCard: View {
    let vehicle: Vehicle?
    let hasActiveWarranty: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VehicleSwitcher()

            Text(vehicle?.displayName ?? "No vehicle selected")
                .font(Theme.Typography.title)

            Text("\((vehicle?.currentOdometer ?? 0).formatted()) mi")
                .font(Theme.Typography.largeTitle)

            HStack {
                if hasActiveWarranty {
                    BadgeView(title: "Under warranty", color: Theme.Colors.success)
                }
                if let fuelType = vehicle?.fuelType {
                    BadgeView(
                        title: fuelType.displayName,
                        color: Theme.Colors.accent
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .garageCard()
    }
}
