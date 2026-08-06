import SwiftUI

/// Tells the owner their car is drinking more than it used to, and what that usually means.
///
/// Sits with the maintenance advisor rather than in Stats because it is the same kind of statement:
/// something the app worked out that the owner did not already know. Stats is where you go to look;
/// the Dashboard is where the car speaks up.
///
/// ## Deliberately not an error banner
///
/// Secondary styling, no red, no icon badge. A 16% drop across three tanks is a reason to check the
/// tire pressures this weekend, not an alarm — and the app cannot tell the difference between a bad
/// wheel bearing and three weeks of short cold trips. Dressing a suggestion as a fault is how a
/// diagnostic surface loses its credibility on the first false positive.
struct FuelEconomyNotice: View {
    let verdict: FuelEconomyAdvisor.Verdict?

    var body: some View {
        if let verdict {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Fuel economy")
                    .font(Theme.Typography.headline)
                Text(message(for: verdict))
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(basis(for: verdict))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .garageCard()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard.fuelEconomy")
        }
    }

    /// "~" on the drop, because the figure is a comparison of two small windows and the causes
    /// listed are the cheap ones to rule out first — in the order a person would actually check
    /// them. No claim is made about which, because the app cannot know.
    private func message(for verdict: FuelEconomyAdvisor.Verdict) -> String {
        "Fuel economy is down ~\(Int(verdict.dropPct.rounded()))% vs your recent average — "
            + "worth checking tire pressures, brakes, or a stuck thermostat."
    }

    /// States what the comparison is made of. A reader who cannot see the denominators cannot
    /// judge the claim, and this one is built from a handful of fill-ups.
    private func basis(for verdict: FuelEconomyAdvisor.Verdict) -> String {
        "Last \(FuelEconomyAdvisor.recentWindow) fill-ups averaged \(verdict.currentAvgMPG.mpgText), "
            + "against \(verdict.baselineAvgMPG.mpgText) across your last \(FuelEconomyAdvisor.baselineWindow)."
    }
}
