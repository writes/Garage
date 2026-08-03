import SwiftUI

/// Pro-gated accent picker (Phase-1 in-Pro theming A/B). Selecting a scheme writes only the
/// themeID field (partial write) via ProfileViewModel and live-recolors the app through
/// AccentStore. Free users see the Pro gate plus a LOCKED preview of the same swatch grid —
/// tester feedback was "themes don't do anything", which is literally what a text-only gate
/// card looks like. The preview is marketing; the gate is still enforcement, so no scheme is
/// ever applied for a non-subscriber.
struct ThemePickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    // This screen owns its own ProfileViewModel. It must stay a STANDALONE Settings destination:
    // do not embed it alongside UserProfileView (which has its own VM) or the two instances can
    // race a full-profile save() against this partial themeID write and lose the update.
    @State private var profileViewModel = ProfileViewModel()
    @State private var isWriting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if appState.isPro {
                    schemeCard
                } else {
                    ProGateView(
                        title: "Themes are part of Pro",
                        message: "Personalize Garage with curated accent colors that apply everywhere instantly.",
                        actionIdentifier: "theme.gate.cta",
                        source: .themePicker
                    ) {
                        presentPaywall()
                    }
                    schemeCard
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle("Theme")
    }

    private var schemeCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Accent")
                .font(Theme.Typography.headline)
            Text(
                appState.isPro
                    ? "Recolors buttons and highlights across the app, instantly."
                    : "Every accent that comes with Pro. Tap one to see Pro options."
            )
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(ThemePickerRow.rows(isPro: appState.isPro)) { row in
                schemeRow(row)
            }
        }
        .garageCard()
    }

    @ViewBuilder
    private func schemeRow(_ row: ThemePickerRow) -> some View {
        if row.isLocked {
            Button { presentPaywall() } label: { rowLabel(row) }
                .accessibilityIdentifier(row.accessibilityIdentifier)
                .accessibilityLabel("\(row.scheme.displayName), Pro")
                .accessibilityHint("Unlock accent themes with Pro")
        } else {
            Button {
                // Serialize writes: a second tap while one is in flight could roll the live accent
                // back to a stale "previous" on a slow/failed earlier write.
                Task {
                    isWriting = true
                    await profileViewModel.setThemeID(row.scheme.rawValue)
                    isWriting = false
                }
            } label: {
                rowLabel(row)
            }
            .disabled(isWriting)
            .accessibilityIdentifier(row.accessibilityIdentifier)
            .accessibilityAddTraits(AccentStore.shared.scheme == row.scheme ? .isSelected : [])
        }
    }

    /// One row body for both states, so the locked preview is visibly the SAME grid a subscriber
    /// gets — only the trailing affordance and the label emphasis differ. The swatch itself stays
    /// full-strength: the colors are the thing being sold.
    private func rowLabel(_ row: ThemePickerRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(row.scheme.tint)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Theme.Colors.textSecondary.opacity(0.25), lineWidth: 1))
            Text(row.scheme.displayName)
                .foregroundStyle(row.isLocked ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
            Spacer()
            if row.isLocked {
                Image(systemName: "lock.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if AccentStore.shared.scheme == row.scheme {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.Colors.primary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minHeight: 44)
    }

    /// Single paywall entry point for this screen: both the gate CTA and every locked row report
    /// through the same `.themePicker` source, so the surface keeps one exposure denominator
    /// rather than splitting into two half-counted funnels.
    private func presentPaywall() {
        router.present(.subscription(.themePicker))
    }
}

/// The picker's rows as data, so the free-user contract — every scheme still listed, all of them
/// locked, none of them applied — is unit-testable without a view harness.
struct ThemePickerRow: Identifiable, Equatable, Sendable {
    let scheme: AccentScheme
    let isLocked: Bool

    var id: String { scheme.rawValue }

    /// Locked rows live in their own identifier namespace: a tap there opens the paywall rather
    /// than selecting a theme, so a test asserting on `theme.option.*` must never match one.
    var accessibilityIdentifier: String {
        isLocked ? "themes.locked.row.\(scheme.rawValue)" : "theme.option.\(scheme.rawValue)"
    }

    static func rows(isPro: Bool) -> [ThemePickerRow] {
        AccentScheme.allCases.map { ThemePickerRow(scheme: $0, isLocked: !isPro) }
    }
}
