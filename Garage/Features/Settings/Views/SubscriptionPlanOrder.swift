import Foundation

/// Decides the order plans are offered in.
///
/// Annual leads. Annual plans generate roughly twice the revenue per install of monthly
/// (D60 median $0.46 vs $0.24, RevenueCat *State of Subscription Apps 2026*), and the
/// utility/productivity segment under-uses annual-default framing. This is **ordering only** — no
/// plan is hidden, monthly remains one tap away, and nothing about pricing or terms changes.
///
/// Extracted from the view so the rule is unit-testable. RevenueCat returns packages in whatever
/// order the offering is configured in, which is a dashboard setting that can change without a
/// build — so the app must not depend on it.
enum SubscriptionPlanOrder {
    static func ordered(_ plans: OfferingsSnapshot) -> [PackageDTO] {
        // Sorted on a TOTAL order with an explicit tiebreak: Swift's sort is not guaranteed
        // stable, so two same-rank packages would otherwise be free to swap between renders.
        plans.packages.sorted { lhs, rhs in
            let left = rank(lhs), right = rank(rhs)
            if left != right { return left < right }
            return lhs.handle.ordinal < rhs.handle.ordinal
        }
    }

    private static func rank(_ dto: PackageDTO) -> Int {
        switch dto.analyticsProduct {
        case .annual: return 0
        case .monthly: return 1
        }
    }
}
