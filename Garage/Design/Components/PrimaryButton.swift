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
        // The style's two border fields used to be read by the secondary button only — this one
        // ignored them, so a pack could not give the filled control an edge. Control's width is 0
        // and paints nothing, so honouring them here moves no shipped pixel.
        .overlay { style.corner.shape.stroke(style.borderColor, lineWidth: style.borderWidth) }
        .clipShape(style.corner.shape)
    }
}
