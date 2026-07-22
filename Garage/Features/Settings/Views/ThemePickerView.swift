import SwiftUI

/// Pro-gated accent picker (Phase-1 in-Pro theming A/B). Selecting a scheme writes only the
/// themeID field (partial write) via ProfileViewModel and live-recolors the app through
/// AccentStore. Free users see the Pro gate. No color wheel, no custom colors — curated only.
struct ThemePickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var profileViewModel = ProfileViewModel()

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
            Text("Applies everywhere instantly.")
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
            Task { await profileViewModel.setThemeID(scheme.rawValue) }
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
        }
        .accessibilityIdentifier("theme.option.\(scheme.rawValue)")
    }
}
