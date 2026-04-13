import SwiftUI

struct EntryFormScaffold<Content: View>: View {
    let title: String
    @Bindable var viewModel: EntryFormViewModel
    var onSave: () async -> Bool
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BottomSheet(title: title) {
            DateOdometerHeader(
                entryDate: $viewModel.entryDate,
                odometerReading: $viewModel.odometerReading,
                lastKnownOdometer: viewModel.lastKnownOdometer
            )
            content
            CostField(cost: $viewModel.cost)
            ShopDiyToggle(isDiy: $viewModel.isDiy, shopName: $viewModel.shopName)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Notes")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 100)
                    .padding(Theme.Spacing.xs)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            AttachmentPicker(attachmentPaths: $viewModel.attachmentPaths)
            if let error = viewModel.error {
                ErrorBanner(error: error)
            }
            PrimaryButton(title: viewModel.isSaving ? "Saving..." : "Save Entry") {
                Task {
                    if await onSave() {
                        dismiss()
                    }
                }
            }
        }
    }
}
