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
            // Same expression as before, now read from the style so both buttons share ONE
            // definition of what a pack's border is.
            .overlay { style.corner.shape.stroke(style.borderColor, lineWidth: style.borderWidth) }
            .clipShape(style.corner.shape)
    }
}
