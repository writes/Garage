import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
                    .font(Theme.Typography.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.onPrimary)
        .background(Theme.Colors.primary)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
