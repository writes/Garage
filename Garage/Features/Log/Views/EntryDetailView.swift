import SwiftUI

struct EntryDetailView: View {
    let entry: FirestoreEntry
    private let entryService: EntryService

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionError: AppError?

    init(entry: FirestoreEntry, entryService: EntryService = .shared) {
        self.entry = entry
        self.entryService = entryService
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                EntryRowView(entry: entry)
                ForEach(entry.details.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key.humanizedFieldLabel)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Text((entry.details[key]?.value ?? .null).displayString)
                            .font(Theme.Typography.body)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle(entry.entryType.displayName)
        .toolbar {
            // Edit-in-place was deferred after adversarial review: forms never re-seed the
            // type-specific `details` map, so a save-over-existing silently wiped it, and
            // odometer-monotonicity validation/vehicle.currentOdometer corrupt on any entry that
            // isn't the vehicle's current max. The correction path is delete + re-add until
            // per-form details seeding lands. See git history for the removed implementation.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("entry.detail.delete")
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Entry", role: .destructive) {
                Task { await deleteEntry() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes this record. This cannot be undone.")
        }
        .alert(
            "Could Not Delete Entry",
            isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
        ) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError?.errorDescription ?? "Please try again.")
        }
    }

    private func deleteEntry() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await entryService.deleteEntry(entry, updatingVehicle: appState.currentVehicle)
            dismiss()
        } catch {
            deletionError = AppError(from: error)
        }
    }
}
