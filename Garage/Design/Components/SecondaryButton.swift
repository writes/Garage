import SwiftUI

struct SecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(Theme.Typography.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .foregroundStyle(Theme.Colors.primary)
            .background(Theme.Colors.surface)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.primary.opacity(0.15), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
