import SwiftUI

struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        // Reading the pack inside body keeps this reactive to a mid-session kill-switch
        // restyle, same mechanism as Theme.Colors.primary.
        let card = DesignPackStore.shared.pack.components.card
        content
            .padding(card.padding)
            .background(Theme.Colors.surface)
            // The hairline the concept separates panels with. Applied UNCONDITIONALLY rather than
            // behind an `if`: control's width is 0, a zero-width stroke paints nothing, and an
            // overlay does not participate in layout — so control renders exactly as before while
            // the branchless tree keeps one view identity across a live pack swap.
            .overlay { card.corner.shape.stroke(card.borderColor, lineWidth: card.borderWidth) }
            .clipShape(card.corner.shape)
            .shadow(color: .garageShadow, radius: card.shadowRadius, x: 0, y: card.shadowOffset)
    }
}
