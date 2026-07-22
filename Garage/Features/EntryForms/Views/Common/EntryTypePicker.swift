import SwiftUI

struct EntryTypePicker: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        BottomSheet(title: "New Entry") {
            Button {
                router.present(.voiceQuickAdd)
            } label: {
                Label("Speak an Entry", systemImage: "mic.fill")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .accessibilityIdentifier("entry.picker.voice")
            Divider()
            ForEach(EntryType.allCases, id: \.self) { entryType in
                Button {
                    router.present(.entryForm(entryType))
                } label: {
                    Label(entryType.displayName, systemImage: entryType.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .accessibilityIdentifier("entry.picker.\(entryType.rawValue)")
            }
        }
    }
}
