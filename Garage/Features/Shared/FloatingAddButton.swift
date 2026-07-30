import SwiftUI

struct FloatingAddButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        let pack = DesignPackStore.shared.pack
        Button {
            router.present(.entryPicker)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 58, height: 58)
                .foregroundStyle(Theme.Colors.onPrimary)
                .background(Theme.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: pack.fabIsCircular ? 29 : Theme.Radius.lg))
                .shadow(color: .garageShadow, radius: pack.cardShadowRadius, x: 0, y: pack.cardShadowRadius > 0 ? 8 : 0)
        }
        .accessibilityLabel("Add a new log entry")
        .accessibilityIdentifier("entry.add")
    }
}
