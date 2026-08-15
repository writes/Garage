import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var action: () -> Void

    var body: some View {
        let style = DesignPackStore.shared.pack.components.primaryButton
        Button(action: action) {
            Label {
                Text(title)
                    .font(style.labelFont)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.verticalPadding)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Colors.onPrimary)
        .background(Theme.Colors.primary)
        .clipShape(style.corner.shape)
    }
}
