import SwiftUI

extension DesignStructure {
    /// Tabs this pack surfaces — the routing set TabView and deep links must stay inside.
    var visibleTabs: Set<AppTab> { Set(tabs.map(\.tab)) }

    /// Whether this pack carries the full Underhood structural treatment (waves U2′–U4′).
    var usesUnderhoodPresentation: Bool { showsDashboardTrendsRow }

    /// Picks a valid tab when persisted selection or a deep link points at one this pack dropped.
    func normalizedTab(_ selected: AppTab) -> AppTab {
        if visibleTabs.contains(selected) { return selected }
        return tabs.first?.tab ?? .dashboard
    }

    func navigationTitle(for tab: AppTab) -> String {
        item(for: tab)?.title ?? tab.rawValue
    }
}

/// Tab-root chrome: pack-driven navigation title and the settings accessory (arm manifest §2.3).
///
/// MUST be applied INSIDE the tab root's own NavigationStack (on the stack's content, not on the
/// stack) — `.navigationTitle`/`.toolbar` bubble up to the NEAREST ENCLOSING stack, and applied
/// from outside there is none, so both are silently dropped.
struct DesignTabRootChrome: ViewModifier {
    let tab: AppTab
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        let structure = DesignPackStore.shared.pack.structure
        content
            .navigationTitle(structure.navigationTitle(for: tab))
            .toolbar {
                if structure.showsSettingsAccessory {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            // Through the ROUTER, never a local sheet: Settings' own actions
                            // (export, paywall) present router sheets from the root host, which
                            // cannot present over a child-hosted sheet — see Sheet.settings.
                            router.present(.settings)
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("tab.settingsAccessory")
                    }
                }
            }
    }
}

extension View {
    func designTabRootChrome(for tab: AppTab) -> some View {
        modifier(DesignTabRootChrome(tab: tab))
    }
}

/// Hood-only Trends row PUSHING the unmodified Stats surface full-screen (arm manifest §2.2).
///
/// A literal navigation push, exactly as the manifest words it: `StatsContent` is StatsView's
/// entire body extracted so it can live INSIDE the Hood's NavigationStack (pushing the whole
/// StatsView would nest a second stack). A push also keeps Stats' paywall CTA working — it
/// presents a ROUTER sheet, which cannot present over a child-hosted sheet but presents fine
/// over a pushed screen.
struct DashboardTrendsRow: View {
    @State private var isShowingStats = false

    var body: some View {
        Button {
            isShowingStats = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    UnderhoodEyebrow(text: "Trends", accent: true)
                    Text("Cost, MPG, and wear over time")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .garageCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hood.trends.row")
        .navigationDestination(isPresented: $isShowingStats) {
            // Event parity (§3): control's Stats visit fires screenViewed via the tab's didSet.
            // This push is the Underhood arm's only Stats route, so the same semantic event
            // fires here — and ONLY here, so control (which never pushes this) is untouched.
            StatsContent()
                .onAppear {
                    AnalyticsService.shared.track(.screenViewed(screen: .stats))
                }
        }
    }
}
