import SwiftUI

struct RecallAlertBadge: View {
    let openRecallCount: Int

    var body: some View {
        if openRecallCount > 0 {
            BadgeView(
                title: "\(openRecallCount) open recall\(openRecallCount == 1 ? "" : "s")",
                color: Theme.Colors.error
            )
        }
    }
}
