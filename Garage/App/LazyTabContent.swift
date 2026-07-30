import SwiftUI

/// Defers a tab's content — and therefore the `.task` fetches inside it — until the tab is first
/// selected.
///
/// TabView appears every tab's content at launch, so the Dashboard, Log and Stats fetches all
/// fired concurrently before the owner had looked at anything but the Dashboard: three vehicles'
/// worth of entry/wear/reminder/warranty queries to render one screen. Content is built on first
/// selection and KEPT from then on, so scroll position, filters and already-paged history survive
/// tab switches — only the launch fan-out goes away.
///
/// The placeholder is deliberately inert. It must never be an empty state: "No log entries yet"
/// shown for a tab that has not fetched yet is the false-empty-state bug this repo has shipped
/// twice. The screens deferred here branch on their own awaiting-first-load flag for the frame
/// between selection and the first result.
struct LazyTabContent<Content: View>: View {
    let tab: AppTab
    let selection: AppTab
    @ViewBuilder let content: () -> Content
    @State private var loadState = LazyTabLoadState()

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            if loadState.shouldRenderContent {
                content()
            }
        }
        // `initial: true` is what loads the tab that is already selected at launch.
        .onChange(of: selection, initial: true) { _, newSelection in
            loadState.update(isSelected: newSelection == tab)
        }
    }
}

/// One-way latch: a tab that has been selected once keeps its content forever after. Extracted
/// from the view so the rule that matters — content is never torn down by switching away, and
/// never built before the first selection — is unit-testable, mirroring `DashboardVehicleState`.
struct LazyTabLoadState: Equatable {
    private(set) var shouldRenderContent = false

    mutating func update(isSelected: Bool) {
        guard isSelected else { return }
        shouldRenderContent = true
    }
}
