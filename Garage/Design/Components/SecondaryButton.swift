import SwiftUI

struct SecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        let style = DesignPackStore.shared.pack.components.secondaryButton
        Button(title, action: action)
            .font(style.labelFont)
            .frame(maxWidth: .infinity)
            .padding(.vertical, style.verticalPadding)
            .foregroundStyle(Theme.Colors.primary)
            .background(Theme.Colors.surface)
            .overlay {
                style.corner.shape
                    .stroke(Theme.Colors.primary.opacity(style.borderOpacity), lineWidth: style.borderWidth)
            }
            .clipShape(style.corner.shape)
    }
}
