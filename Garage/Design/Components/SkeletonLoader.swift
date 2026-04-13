import SwiftUI

struct SkeletonLoader: View {
    var height: CGFloat = 92

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md)
            .fill(Theme.Colors.secondary.opacity(0.18))
            .frame(height: height)
            .modifier(ShimmerModifier())
    }
}
