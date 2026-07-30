import SwiftUI

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        // Reading the pack inside body keeps this reactive to a mid-session kill-switch
        // restyle, same mechanism as Theme.Colors.primary.
        let pack = DesignPackStore.shared.pack
        content
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: pack.cardRadius))
            .shadow(color: .garageShadow, radius: pack.cardShadowRadius, x: 0, y: pack.cardShadowRadius > 0 ? 6 : 0)
    }
}
