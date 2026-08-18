import SwiftUI

/// One service-light chip from the concept's `.light` row (arm manifest §2.4).
struct ServiceLightPill: View {
    enum Severity {
        case okay, warn, bad

        // Theme tokens resolve through the MainActor-isolated pack store, and every caller is
        // view body code, so the isolation belongs on the accessor.
        @MainActor var color: Color {
            switch self {
            case .okay: return Theme.Colors.success
            case .warn: return Theme.Colors.warning
            case .bad: return Theme.Colors.error
            }
        }
    }

    let label: String
    let severity: Severity

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(severity.color)
                .frame(width: 7, height: 7)
                .shadow(color: severity == .okay ? .clear : severity.color.opacity(0.6), radius: 4)
            Text(label.uppercased())
                .font(Theme.Typography.caption.weight(.semibold))
                .fontDesign(.monospaced)
                .tracking(0.5)
        }
        .foregroundStyle(severity.color)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface)
        .overlay {
            DesignPackStore.shared.pack.components.card.corner.shape
                .stroke(Theme.Colors.textPrimary.opacity(0.10), lineWidth: 1)
        }
        .clipShape(DesignPackStore.shared.pack.components.card.corner.shape)
        .accessibilityElement(children: .combine)
    }
}
