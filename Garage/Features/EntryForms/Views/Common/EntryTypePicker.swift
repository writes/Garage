import SwiftUI

struct EntryTypePicker: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        BottomSheet(title: "New Entry") {
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
