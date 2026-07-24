import SwiftUI

struct EntryDetailView: View {
    let entry: FirestoreEntry
    private let entryService: EntryService

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
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
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .navigationTitle(entry.entryType.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("entry.detail.delete")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    // Same "present the next sheet, then dismiss this one" ordering
                    // presentVoicePrefilledForm uses when VoiceQuickAddView hands off to a form.
                    router.presentEditForm(for: entry)
                    dismiss()
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("entry.detail.edit")
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
