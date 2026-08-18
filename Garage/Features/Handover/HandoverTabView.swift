import SwiftUI

/// Handover tab root — the same export engine as control, reframed per the arm manifest §2.8.
struct HandoverTabView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    handoverHeader
                    ExportView(embeddedInTab: true)
                }
                .padding(Theme.Spacing.md)
            }
            .background(Theme.Colors.background.ignoresSafeArea())
            .designTabRootChrome(for: .handover)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
            // Event parity (§3): control reaches this surface via router.present(.export), which
            // fires formOpened(.export). This tab hosts the same surface without the router, so
            // the SAME semantic event fires per visit (onAppear re-fires on each tab switch-in,
            // matching control's per-open cadence). Control never mounts this tab — no double-fire.
            .onAppear {
                AnalyticsService.shared.track(.formOpened(form: .export))
            }
        }
    }

    @ViewBuilder
    private var handoverHeader: some View {
        let framing = DesignPackStore.shared.pack.structure.framing
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            UnderhoodEyebrow(text: "Owner-controlled dossier", accent: true)
            Text(framing.handoverTitle ?? "Handover")
                .font(Theme.Typography.title)
            if let subtitle = framing.handoverSubtitle {
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Record tab placeholder — selection immediately routes to the entry picker (ContentView).
struct RecordTabPlaceholder: View {
    var body: some View {
        Color.clear
            .accessibilityIdentifier("tab.record.placeholder")
    }
}
