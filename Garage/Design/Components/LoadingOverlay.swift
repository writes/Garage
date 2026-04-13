import SwiftUI

struct LoadingOverlay: View {
    var label = "Loading"

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            ProgressView()
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .garageCard()
    }
}
