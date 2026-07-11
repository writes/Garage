import SwiftUI

struct BottomSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    content
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Close") {
                    dismiss()
                }
                .accessibilityIdentifier("sheet.dismiss")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
