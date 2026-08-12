import SwiftUI

struct FloatingAddButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        let style = DesignPackStore.shared.pack.components.floatingButton
        Button {
            router.present(.entryPicker)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: style.iconPointSize, weight: style.iconWeight))
                .frame(width: style.diameter, height: style.diameter)
                .foregroundStyle(Theme.Colors.onPrimary)
                .background(Theme.Colors.primary)
                .clipShape(style.corner.shape)
                .shadow(color: .garageShadow, radius: style.shadowRadius, x: 0, y: style.shadowOffset)
        }
        .accessibilityLabel("Add a new log entry")
        .accessibilityIdentifier("entry.add")
    }
}
