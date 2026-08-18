import SwiftUI

/// One chamfered tile in the Systems Bay grid (concept `.tile`).
struct SystemsBayTileView: View {
    let tile: SystemsBayTile

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(tile.name)
                .font(Theme.Typography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(tile.dueText.uppercased())
                .font(Theme.Typography.caption.weight(.semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(statusColor)
            Text(tile.lastText)
                .font(Theme.Typography.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(Theme.Colors.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Theme.Colors.secondary.opacity(0.18))
                    Rectangle()
                        .fill(statusColor)
                        .frame(width: geo.size.width * tile.progress)
                }
            }
            .frame(height: 3)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surface)
        .overlay {
            DesignCorner(radius: 0, chamfer: 12).shape
                .stroke(Theme.Colors.textPrimary.opacity(0.10), lineWidth: 1)
        }
        .clipShape(DesignCorner(radius: 0, chamfer: 12).shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("systemsBay.tile.\(tile.id)")
    }

    private var statusColor: Color {
        switch tile.status {
        case .okay: return Theme.Colors.success
        case .warn: return Theme.Colors.warning
        case .bad: return Theme.Colors.error
        }
    }
}

struct SystemsBayGridView: View {
    let tiles: [SystemsBayTile]

    private let columns = [
        GridItem(.flexible(), spacing: Theme.Spacing.sm),
        GridItem(.flexible(), spacing: Theme.Spacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            ForEach(tiles) { tile in
                SystemsBayTileView(tile: tile)
            }
        }
    }
}
