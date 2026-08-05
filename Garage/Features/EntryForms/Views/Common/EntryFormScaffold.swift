import Foundation
import Observation
import SwiftUI

// Oil-analysis draft/mutation-gating types (EntryFormMutationGating, OilAnalysisDraft, etc.) live
// in OilAnalysisDraft.swift — split out to stay under this file's cap.

struct EntryFormScaffold<Content: View>: View {
    let title: String
    @Bindable var viewModel: EntryFormViewModel
    var onSave: () async -> Bool
    /// Fires once, only when opened via AppRouter.presentEditForm(for:) — mirrors onSave as the
    /// per-form opt-in point. Each form's own seed(from:) reads its own `entry.details` keys.
    var onEditEntry: ((FirestoreEntry) -> Void)?
    /// Fires once per seeded presentation, only when a voice/receipt handoff opened this form —
    /// the typed-extraction mirror of onEditEntry. Each form maps the raw wire values it cares
    /// about through its own explicit conversion tables; common fields (shop, cost, date…) are
    /// already applied to the view model by the time this runs, so a form may read those too.
    var onAIPrefill: ((TypedProposalDetails) -> Void)?
    /// Nil by default so every non-oil form preserves its existing behavior. The oil-analysis
    /// form opts in to live epoch-checked bindings while an authorized import owns its draft.
    var mutationGate: (any EntryFormMutationGating)?
    @ViewBuilder var content: Content

    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    /// Belt-and-braces for the zero-vehicle audit finding: AppRouter.present already redirects
    /// .entryForm to vehicle creation when there are no vehicles, so this only fires in the
    /// narrow window where a vehicle is removed (e.g. from another device) while this sheet is
    /// still open — the per-form `save()` closures each `guard let vehicle = appState
    /// .currentVehicle else { return false }` silently, with no other visible feedback.
    @State private var noVehicleError: AppError?

    init(
        title: String,
        viewModel: EntryFormViewModel,
        onSave: @escaping () async -> Bool,
        onEditEntry: ((FirestoreEntry) -> Void)? = nil,
        onAIPrefill: ((TypedProposalDetails) -> Void)? = nil,
        mutationGate: (any EntryFormMutationGating)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _viewModel = Bindable(wrappedValue: viewModel)
        self.onSave = onSave
        self.onEditEntry = onEditEntry
        self.onAIPrefill = onAIPrefill
        self.mutationGate = mutationGate
        self.content = content()
    }

    var body: some View {
        BottomSheet(title: title) {
            DateOdometerHeader(
                entryDate: guardedBinding($viewModel.entryDate),
                odometerReading: guardedBinding($viewModel.odometerReading),
                lastKnownOdometer: odometerHint,
                isEditing: viewModel.editingEntryID != nil
            )
            .disabled(isMutationLocked)
            if let caption = viewModel.unreadReceiptFieldsCaption {
                Text(caption)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("entry.form.receipt.unreadFields")
            }
            // The persistent half of the consent design: this form IS the confirm step for both
            // voice and receipt, so whatever the model filled in is labelled where it is reviewed.
            if viewModel.wasVoiceSeeded || viewModel.wasReceiptSeeded {
                AIDisclosureCaption(identifier: "entry.form.aiDisclosure")
            }
            content
            attachmentsSection
                .disabled(isMutationLocked)
            CostField(cost: guardedBinding($viewModel.cost))
                .disabled(isMutationLocked)
            ShopDiyToggle(
                isDiy: guardedBinding($viewModel.isDiy),
                shopName: guardedBinding($viewModel.shopName)
            )
            .disabled(isMutationLocked)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Notes")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                TextEditor(text: guardedBinding($viewModel.notes))
                    .frame(minHeight: 100)
                    .padding(Theme.Spacing.xs)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .accessibilityIdentifier("entry.form.notes")
            }
            .disabled(isMutationLocked)
            if let error = viewModel.error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("entry.form.error")
            } else if let noVehicleError {
                ErrorBanner(error: noVehicleError)
                    .accessibilityIdentifier("entry.form.error")
            }
            PrimaryButton(title: viewModel.isSaving ? "Saving..." : "Save Entry") {
                Task {
                    await saveIfAdmitted()
                }
            }
            .disabled(viewModel.isSaving || !canAdmitSave)
            .accessibilityIdentifier("entry.form.save")
        }
        .accessibilityIdentifier("entry.form.sheet")
        .task {
            // Peek, don't consume: SwiftUI may build this sheet's content more than once during
            // the voice/receipt→form swap, and a fresh build means a fresh EntryFormViewModel —
            // consuming on the first (possibly throwaway) build left the surviving form blank on
            // device. The router holds the slot for the whole presentation; the seeded flags keep
            // a same-viewModel re-run from clobbering the user's edits.
            var aiDetails: TypedProposalDetails?
            if !viewModel.wasVoiceSeeded, let prefill = router.pendingVoicePrefill {
                viewModel.applyVoicePrefill(prefill)
                aiDetails = prefill.typed
            }
            // Same held-slot pattern, kept as its own slot (never both — see wasReceiptSeeded).
            if !viewModel.wasReceiptSeeded, let package = router.pendingReceiptPrefill {
                viewModel.applyReceiptPrefill(package, isPro: appState.isPro)
                aiDetails = package.proposal.typed
            }
            // After the common apply (so forms can read shop/cost off the view model), before
            // prepare() (same ordering rationale as the edit seed below).
            if let aiDetails { onAIPrefill?(aiDetails) }
            // Same pattern for edit-in-place. Sequenced strictly before prepare() below (same
            // task, in order) so editingEntryID is always set before prepare() reads it — no
            // ordering race against a form's own separate .task, which two independent .task
            // blocks could not guarantee.
            if viewModel.editingEntryID == nil, let editEntry = router.pendingEditEntry {
                viewModel.applyExistingEntry(editEntry)
                onEditEntry?(editEntry)
            }
            // Centralized (not per-form) so every form gets it for free, always after the above.
            if let vehicleId = appState.currentVehicle?.id {
                await viewModel.prepare(vehicleId: vehicleId)
            }
            viewModel.captureReceiptPrefillBaseline()
        }
        // The odometer's legal range depends on the DATE being logged, so it has to follow the
        // picker. prepare() derives it once, at open; without this a user who backdates an entry
        // is still validated against the range for the date the form happened to open with.
        .onChange(of: viewModel.entryDate) {
            guard let vehicleId = appState.currentVehicle?.id else { return }
            Task { await viewModel.refreshOdometerBounds(vehicleId: vehicleId) }
        }
    }

    private var isMutationLocked: Bool {
        mutationGate?.isMutationLocked ?? false
    }

    /// Demo/UI-test mode is checked BEFORE the Pro gate and hides the section outright — there's
    /// no real Storage there, and EntryCreateJourneyTests
    /// .testFuelEntryFormRetainsSaveAndHidesAttachmentPersistenceUI (launched with UI_TEST_PRO,
    /// i.e. isPro == true) asserts no attachment control or text is reachable at all.
    @ViewBuilder
    private var attachmentsSection: some View {
        if !AppRuntime.isLocalDemoMode {
            if appState.isPro {
                AttachmentPicker(viewModel: viewModel)
            } else {
                ProGateView(
                    title: "Attachments are part of Pro",
                    message: "Attach receipts, invoices, and photos to your entries with Garage Pro.",
                    actionIdentifier: "entry.form.attachments.gate",
                    source: .attachments
                ) {
                    router.present(.subscription(.attachments))
                }
                if viewModel.receiptAttachmentNeedsPro {
                    Text("Garage Pro keeps the original receipt attached to this entry.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("entry.form.attachments.receiptUpsell")
                }
            }
        }
    }

    /// Create shows the vehicle's highest recorded reading as CONTEXT, not a limit — a backdated
    /// entry below it is legal. Edit shows the floor the validator will actually enforce
    /// (DateOdometerHeader picks the matching label for whichever this is).
    private var odometerHint: Int? {
        viewModel.editingEntryID == nil
            ? viewModel.lastKnownOdometer
            : viewModel.validationBounds.earlier?.reading
    }

    private var canAdmitSave: Bool {
        guard let mutationGate else { return true }
        return mutationGate.canCommitSave(epoch: mutationGate.mutationEpoch)
    }

    /// The captured epoch is intentionally checked at assignment time. SwiftUI can deliver an
    /// old text, photo, or file-import callback after the render that created its binding.
    private func guardedBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        guard let mutationGate else { return binding }
        let epoch = mutationGate.mutationEpoch
        return Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard mutationGate.acceptsUserMutation(epoch: epoch) else { return }
                binding.wrappedValue = value
            }
        )
    }

    private func saveIfAdmitted() async {
        guard let mutationGate else {
            let didSave = await onSave()
            if didSave {
                // Before dismissSheet, and on a counter that outlives this sheet: the confirmation
                // is for a save that already succeeded, and this view is gone a frame later.
                FeedbackCenter.shared.fire(.success)
                router.dismissSheet()
            } else {
                flagMissingVehicleIfNeeded()
            }
            return
        }

        guard let epoch = mutationGate.beginSave(), mutationGate.canCommitSave(epoch: epoch) else {
            return
        }
        let didSave = await onSave()
        guard didSave, mutationGate.canCommitSave(epoch: epoch) else {
            flagMissingVehicleIfNeeded()
            return
        }
        // Gated path: only after the epoch re-check, so a save superseded mid-flight stays silent.
        FeedbackCenter.shared.fire(.success)
        router.dismissSheet()
    }

    /// Only surfaces the banner when the failed save is otherwise unexplained (no viewModel
    /// error already latched) and the vehicle really is gone — never masks a real save error.
    private func flagMissingVehicleIfNeeded() {
        guard viewModel.error == nil, appState.currentVehicle == nil else { return }
        noVehicleError = .validation("Select a vehicle first")
    }
}
