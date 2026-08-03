import SwiftUI

/// The one-time first-use consent prompt shown before voice quick-add or a receipt scan uploads
/// anything. Copy and interaction mirror `OilAnalysisConsentSheet` — the flow that already asked —
/// so all three AI surfaces read as one product decision rather than three.
struct AIConsentSheet: View {
    let continueTapped: () -> Void
    let notNowTapped: () -> Void

    /// Same double-tap claim OilAnalysisConsentSheet uses: the toolbar stays live for a frame
    /// after the first tap, and a second one would run the parked upload twice.
    @State private var didClaimAction = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Use AI to fill in your entry?")
                    .font(Theme.Typography.headline)
                Text(
                    "Garage sends what you capture — the words you speak, or the receipt you "
                        + "photograph — to Anthropic's Claude API, which reads it and returns the "
                        + "details for your entry."
                )
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                Text(
                    "Nothing is sent until you allow it, you review and edit every entry before "
                        + "it is saved, and you can turn this off any time in Settings."
                )
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                AIDisclosureCaption()
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("AI Features")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("ai.consent.sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now", role: .cancel) {
                        guard !didClaimAction else { return }
                        didClaimAction = true
                        notNowTapped()
                    }
                    .accessibilityIdentifier("ai.consent.notNow")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        guard !didClaimAction else { return }
                        didClaimAction = true
                        continueTapped()
                    }
                    .disabled(didClaimAction)
                    .accessibilityIdentifier("ai.consent.continue")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
