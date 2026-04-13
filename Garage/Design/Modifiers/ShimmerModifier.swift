import SwiftUI

struct ShimmerModifier: ViewModifier {
    @State private var startPoint: UnitPoint = .leading
    @State private var endPoint: UnitPoint = .trailing

    func body(content: Content) -> some View {
        content
            .overlay {
                LinearGradient(
                    colors: [.clear, .white.opacity(0.4), .clear],
                    startPoint: startPoint,
                    endPoint: endPoint
                )
                .blendMode(.plusLighter)
            }
            .task {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    startPoint = .init(x: 1, y: 0)
                    endPoint = .init(x: 2, y: 0)
                }
            }
    }
}
