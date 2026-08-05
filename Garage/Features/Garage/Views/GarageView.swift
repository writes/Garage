import SwiftUI

struct GarageView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                if !appState.isPro {
                    ProGateView(
                        title: "Garage tools are part of Pro",
                        message: """
                        Spare parts, detailing, warranty, and recalls
                        are unlocked with Pro.
                        """,
                        actionIdentifier: "garage.gate.cta",
                        source: .garage
                    ) {
                        router.present(.subscription(.garage))
                    }
                    .listRowSeparator(.hidden)
                } else {
                    // Gallery and Wheel records have no write path on this build, so they are
                    // labelled as unshipped rather than listed as peers of the three rows below
                    // that hold real data. The rows stay reachable: the screens explain the state
                    // in place, which is a better answer than a row that silently disappears.
                    NavigationLink { PhotoGalleryView() } label: {
                        comingSoonLabel("Gallery Records")
                    }
                    .accessibilityIdentifier("garage.gallery")
                    // The spoken "Coming soon" lives here; the visual "Soon" badge is
                    // accessibilityHidden so VoiceOver says it exactly once. Also the
                    // journeys' stable assertion target.
                    .accessibilityValue("Coming soon")
                    NavigationLink { WheelGalleryView() } label: {
                        comingSoonLabel("Wheel Records")
                    }
                    .accessibilityIdentifier("garage.wheels")
                    .accessibilityValue("Coming soon")
                    NavigationLink("Spare Parts") { SparePartsView() }
                        .accessibilityIdentifier("garage.parts")
                    NavigationLink("Detailing Log") { DetailingLogView() }
                        .accessibilityIdentifier("garage.detailing")
                    NavigationLink("Warranty & Recalls") { WarrantyRecallView() }
                        .accessibilityIdentifier("garage.warranty")
                }
            }
            .navigationTitle("Garage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
        }
    }

    /// Trailing "Soon" rather than a disabled row. The visual badge is hidden from VoiceOver:
    /// the label auto-combines its Texts, so without this the row reads "…, Soon, Coming soon" —
    /// the accessibilityValue on the link is the single spoken source (cross-check).
    private func comingSoonLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("Soon")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityHidden(true)
        }
    }
}
