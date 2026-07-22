import SwiftUI

/// Pro-gated accent picker (Phase-1 in-Pro theming A/B). Selecting a scheme writes only the
/// themeID field (partial write) via ProfileViewModel and live-recolors the app through
/// AccentStore. Free users see the Pro gate. No color wheel, no custom colors — curated only.
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
                        actionIdentifier: "theme.gate.cta"
                    ) {
                        router.present(.subscription(.themePicker))
                    }
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
            Text("Recolors buttons and highlights across the app, instantly.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(AccentScheme.allCases) { scheme in
                schemeRow(scheme)
            }
        }
        .garageCard()
    }

    private func schemeRow(_ scheme: AccentScheme) -> some View {
        Button {
            // Serialize writes: a second tap while one is in flight could roll the live accent
            // back to a stale "previous" on a slow/failed earlier write.
            Task {
                isWriting = true
                await profileViewModel.setThemeID(scheme.rawValue)
                isWriting = false
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Circle()
                    .fill(scheme.tint)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Theme.Colors.textSecondary.opacity(0.25), lineWidth: 1))
                Text(scheme.displayName)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if AccentStore.shared.scheme == scheme {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: 44)
        }
        .disabled(isWriting)
        .accessibilityIdentifier("theme.option.\(scheme.rawValue)")
        .accessibilityAddTraits(AccentStore.shared.scheme == scheme ? .isSelected : [])
    }
}
