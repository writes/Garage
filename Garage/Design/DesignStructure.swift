import Foundation

/// One tab as the pack configures it: which shipped root it hosts (`tab`) and how it is labelled.
/// Order is the order of the array holding these, so a pack re-orders or drops a tab without a
/// call-site edit.
///
/// Keyed on `AppTab` because every arm hosts the SAME view hierarchy per tab (arm manifest §2.1) —
/// a re-mapped arm renames and re-orders the shipped roots, it does not fork them. The identities
/// the concept adds (Record, Handover) arrive with wave U4′, as `AppTab` cases.
struct DesignTabItem: Equatable, Sendable, Identifiable {
    let tab: AppTab
    let title: String
    let systemImage: String

    var id: AppTab { tab }
}

/// Copy a pack RE-FRAMES (arm manifest §2.7 Record, §2.8 Handover). `nil` — control everywhere —
/// means the shipped copy stands: a pack that restated control's own strings here would be a
/// second source of truth for them, and the two would drift.
struct DesignFraming: Equatable, Sendable {
    let recordTitle: String?
    let recordSubtitle: String?
    let handoverTitle: String?
    let handoverSubtitle: String?
}

/// The CLOSED list of STRUCTURAL differences a pack may carry (arm manifest §2). Anything absent
/// from this type renders identically in every arm — that is the whole parity contract, so it
/// gains a member only through a manifest amendment, never through a convenient one-off.
///
/// Phase 1 wires exactly one consumer (`tabs`, read by the main tab view) and control's values are
/// the shipped behaviour throughout, so the chokepoint is proven without anything moving.
struct DesignStructure: Equatable, Sendable {
    let tabs: [DesignTabItem]
    /// Dashboard gains a "Trends" row pushing the unmodified `StatsView` (arm manifest §2.2).
    let showsDashboardTrendsRow: Bool
    /// Every tab root's nav bar gains an accessory presenting the unmodified `SettingsView`
    /// (arm manifest §2.3).
    let showsSettingsAccessory: Bool
    let framing: DesignFraming

    /// The item for a tab, or nil when this pack does not surface it. Callers that must render a
    /// known tab regardless (deep links) keep working off `AppTab` itself.
    func item(for tab: AppTab) -> DesignTabItem? {
        tabs.first { $0.tab == tab }
    }
}
