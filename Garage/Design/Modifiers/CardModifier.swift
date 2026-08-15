import SwiftUI

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        // Reading the pack inside body keeps this reactive to a mid-session kill-switch
        // restyle, same mechanism as Theme.Colors.primary.
        let card = DesignPackStore.shared.pack.components.card
        content
            .padding(card.padding)
            .background(Theme.Colors.surface)
            .clipShape(card.corner.shape)
            .shadow(color: .garageShadow, radius: card.shadowRadius, x: 0, y: card.shadowOffset)
    }
}
