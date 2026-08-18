import SwiftUI

struct GarageView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    private var usesUnderhood: Bool {
        DesignPackStore.shared.pack.structure.usesUnderhoodPresentation
    }

    var body: some View {
        NavigationStack {
            Group {
                if usesUnderhood {
                    bayScrollContent
                } else {
                    controlListContent
                }
            }
            // Underhood-only paint: control's List kept the system background before this wave,
            // and the control baseline is pinned — Color.clear is the identity-stable no-op.
            .background(
                (usesUnderhood ? Theme.Colors.background : Color.clear).ignoresSafeArea()
            )
            // In-stack chrome: "Garage" in control, "Bay" in Underhood, plus the §2.3 settings
            // accessory (control's flag is off, so its bar is untouched).
            .designTabRootChrome(for: .garage)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
        }
    }

    private var controlListContent: some View {
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
                NavigationLink { PhotoGalleryView() } label: {
                    comingSoonLabel("Gallery Records")
                }
                .accessibilityIdentifier("garage.gallery")
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
    }

    private var bayScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                UnderhoodEyebrow(text: "The physical shelf", accent: true)
                Text("Parts, warranties, and records for everything bolted to the car.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if !appState.isPro {
                    ProGateView(
                        title: "Bay tools are part of Pro",
                        message: "Spare parts, detailing, warranty, and recalls unlock with Pro.",
                        actionIdentifier: "garage.gate.cta",
                        source: .garage
                    ) {
                        router.present(.subscription(.garage))
                    }
                    .garageCard()
                } else {
                    bayTileGrid
                }
            }
            .padding(Theme.Spacing.md)
        }
    }

    private var bayTileGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: Theme.Spacing.sm),
            GridItem(.flexible(), spacing: Theme.Spacing.sm)
        ]
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            bayLink(title: "Spare Parts", subtitle: "Shelf inventory", id: "garage.parts") {
                SparePartsView()
            }
            bayLink(title: "Detailing", subtitle: "Care log", id: "garage.detailing") {
                DetailingLogView()
            }
            bayLink(title: "Warranty", subtitle: "Coverage + recalls", id: "garage.warranty") {
                WarrantyRecallView()
            }
            // The unshipped rows stay REACHABLE (their screens explain the state in place) and
            // keep the same spoken "Coming soon" as control's list — §4 parity is identifiers AND
            // announced semantics, not just the visual shell.
            bayLink(title: "Gallery", subtitle: "Coming soon", id: "garage.gallery", value: "Coming soon") {
                PhotoGalleryView()
            }
            bayLink(title: "Wheels", subtitle: "Coming soon", id: "garage.wheels", value: "Coming soon") {
                WheelGalleryView()
            }
        }
    }

    private func bayLink<Destination: View>(
        title: String,
        subtitle: String,
        id: String,
        value: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle.uppercased())
                    .font(Theme.Typography.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(value != nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.sm)
            .background(Theme.Colors.surface)
            .overlay {
                DesignCorner(radius: 0, chamfer: 12).shape
                    .stroke(Theme.Colors.textPrimary.opacity(0.10), lineWidth: 1)
            }
            .clipShape(DesignCorner(radius: 0, chamfer: 12).shape)
        }
        // .plain, and the title painted explicitly: a NavigationLink label outside a List renders
        // its untinted Texts in the accent otherwise.
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(value ?? "")
    }

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
