import SwiftUI

struct EntryDetailView: View {
    let entry: FirestoreEntry
    private let entryService: EntryService
    private let entryAttachmentService: EntryAttachmentService

    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionError: AppError?

    init(
        entry: FirestoreEntry,
        entryService: EntryService = .shared,
        entryAttachmentService: EntryAttachmentService = .shared
    ) {
        self.entry = entry
        self.entryService = entryService
        self.entryAttachmentService = entryAttachmentService
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
                if !entry.attachmentPaths.isEmpty {
                    attachmentsSection
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

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Attachments")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(entry.attachmentPaths, id: \.self) { path in
                AttachmentDetailRow(path: path, entryAttachmentService: entryAttachmentService)
            }
        }
    }

    private func deleteEntry() async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            // Attachment cascade lives at the SERVICE layer now (EntryService+Mutations.swift's
            // cascadeDeleteAttachments) — review BLOCKER: a view-layer-only cascade here missed
            // LogView's swipe-delete, which calls deleteEntry directly. Do not re-add a cascade
            // call here; there must be exactly one cascade site.
            try await entryService.deleteEntry(entry, updatingVehicle: appState.currentVehicle)
            dismiss()
        } catch {
            deletionError = AppError(from: error)
        }
    }
}

/// PDFs render as a labeled row (icon + filename) — no QuickLook this pass (future work). Images
/// resolve a downloadURL and show an async thumbnail; failures fall back to a placeholder icon
/// rather than an empty gap.
private struct AttachmentDetailRow: View {
    let path: String
    let entryAttachmentService: EntryAttachmentService
    @State private var downloadURL: URL?

    private var isPDF: Bool { path.hasSuffix(".pdf") }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if isPDF {
                Image(systemName: "doc.fill")
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text((path as NSString).lastPathComponent)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
            } else {
                thumbnail
                Text("Photo")
                    .font(Theme.Typography.caption)
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .task {
            guard !isPDF else { return }
            downloadURL = try? await entryAttachmentService.downloadURL(for: path)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let downloadURL {
            AsyncImage(url: downloadURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderIcon
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            ProgressView()
                .frame(width: 44, height: 44)
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "photo")
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}
