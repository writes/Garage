import SwiftUI

/// The concept's `.p-eyebrow`: mono, uppercase, tracked — section labels in the Underhood world.
struct UnderhoodEyebrow: View {
    let text: String
    var accent: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typography.caption.weight(.semibold))
            .fontDesign(.monospaced)
            .tracking(1.4)
            .foregroundStyle(accent ? Theme.Colors.primary : Theme.Colors.textSecondary)
    }
}
