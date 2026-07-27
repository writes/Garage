import SwiftUI

struct FloatingAddButton: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            router.present(.entryPicker)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .frame(width: 58, height: 58)
                .foregroundStyle(Theme.Colors.onPrimary)
                .background(Theme.Colors.primary)
                .clipShape(Circle())
                .shadow(color: .garageShadow, radius: 10, x: 0, y: 8)
        }
        .accessibilityLabel("Add a new log entry")
        .accessibilityIdentifier("entry.add")
    }
}
