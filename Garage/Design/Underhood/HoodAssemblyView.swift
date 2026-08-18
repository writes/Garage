import SwiftUI

/// Hood card that hinges open to reveal the Systems Bay (arm manifest §2.4).
///
/// The closed hood carries only the vehicle name and the reveal affordance — no stat row. The
/// prototype's record/evidence/history figures have no honest source here (recent entries are a
/// capped page, not a total; the vehicle's createdAt is an app date, not ownership history), and
/// the house rule is honest-nil over invented numbers.
struct HoodAssemblyView: View {
    let vehicleName: String
    let tiles: [SystemsBayTile]
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // Opacity/hit-testing hide the inactive layer visually but NOT from VoiceOver —
            // without the explicit accessibilityHidden pair, assistive tech can reach and
            // activate controls inside the invisible layer.
            bayContent
                .opacity(isOpen ? 1 : 0)
                .allowsHitTesting(isOpen)
                .accessibilityHidden(!isOpen)
            hoodCard
                .rotation3DEffect(
                    .degrees(isOpen ? 64 : 0),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .top,
                    perspective: 0.55
                )
                .opacity(isOpen ? 0.04 : 1)
                .allowsHitTesting(!isOpen)
                .accessibilityHidden(isOpen)
        }
        .frame(minHeight: isOpen ? 340 : 180)
        .animation(reduceMotion ? .none : .spring(response: 0.8, dampingFraction: 0.85), value: isOpen)
        .accessibilityElement(children: .contain)
    }

    private var bayContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            UnderhoodEyebrow(text: "Systems bay", accent: true)
            SystemsBayGridView(tiles: tiles)
            // The same disclaimer control's MaintenanceDueCard carries — the bay restyles that
            // card, and the advice caveat is part of the information, not the styling.
            Text("Based on common service intervals — your owner's manual takes precedence.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Close the hood ↑") { isOpen = false }
                .font(Theme.Typography.caption.weight(.semibold))
                .fontDesign(.monospaced)
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("hood.closeBay")
        }
    }

    private var hoodCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                UnderhoodEyebrow(text: "The record so far")
                Text(vehicleName)
                    .font(Theme.Typography.title)
            }
            Button {
                isOpen = true
            } label: {
                Label("Pop the hood", systemImage: "chevron.up")
                    .font(Theme.Typography.caption.weight(.bold))
                    .fontDesign(.monospaced)
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .overlay {
                        RoundedRectangle(cornerRadius: 0)
                            .stroke(Theme.Colors.primary, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hood.popHood")
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // surface → background, the same one-step ramp the page itself uses. (`opacity` above 1
        // just clamps, so "a lighter surface" cannot be spelled that way.)
        .background(
            LinearGradient(
                colors: [Theme.Colors.surface, Theme.Colors.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            DesignCorner(radius: 0, chamfer: 22).shape
                .stroke(Theme.Colors.textPrimary.opacity(0.10), lineWidth: 1)
        }
        .clipShape(DesignCorner(radius: 0, chamfer: 22).shape)
    }
}
