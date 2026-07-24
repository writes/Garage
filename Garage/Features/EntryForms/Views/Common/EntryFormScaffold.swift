import Foundation
import Observation
import SwiftUI

@MainActor
protocol EntryFormMutationGating: AnyObject {
    var mutationEpoch: UInt64 { get }
    var isMutationLocked: Bool { get }
    func acceptsUserMutation(epoch: UInt64) -> Bool
    func beginSave() -> UInt64?
    func canCommitSave(epoch: UInt64) -> Bool
}

struct OilAnalysisImportPrefill: Equatable, Sendable {
    let labName: String
    let viscosity: String?
    let milesOnOil: Int?
    let iron: Double?
    let aluminum: Double?
    let labRecommendation: String?

    init(entry: OilAnalysisEntry) {
        labName = entry.labName
        viscosity = entry.viscosity
        milesOnOil = entry.milesOnOil
        iron = entry.iron
        aluminum = entry.aluminum
        labRecommendation = entry.labRecommendation
    }
}

struct OilAnalysisEditableFields: Equatable, Sendable {
    var labName = "Blackstone"
    var viscosity = ""
    var milesOnOil = ""
    var iron = ""
    var aluminum = ""
    var labRecommendation = ""

    mutating func apply(_ prefill: OilAnalysisImportPrefill) {
        labName = prefill.labName
        if let viscosity = prefill.viscosity { self.viscosity = viscosity }
        if let milesOnOil = prefill.milesOnOil { self.milesOnOil = String(milesOnOil) }
        if let iron = prefill.iron { self.iron = String(iron) }
        if let aluminum = prefill.aluminum { self.aluminum = String(aluminum) }
        if let labRecommendation = prefill.labRecommendation {
            self.labRecommendation = labRecommendation
        }
    }
}

enum OilAnalysisImportOutcome: Equatable, Sendable {
    case idle
    case prefill(OilAnalysisImportPrefill)
    case showPaywall
    case syncPending
    case dailyQuota(resetAt: Date)
    case inlineError(AppError)
}

@MainActor
@Observable
final class OilAnalysisDraft: OilAnalysisPrefillApplying {
    var editableFields = OilAnalysisEditableFields()
    private var authorizedOwnerID: UUID?

    func textBinding(
        _ keyPath: WritableKeyPath<OilAnalysisEditableFields, String>,
        gate: any EntryFormMutationGating
    ) -> Binding<String> {
        let epoch = gate.mutationEpoch
        return Binding(
            get: { self.editableFields[keyPath: keyPath] },
            set: { [weak self, weak gate] value in
                guard let self, let gate, gate.acceptsUserMutation(epoch: epoch) else { return }
                self.editableFields[keyPath: keyPath] = value
            }
        )
    }

    func beginAuthorizedImport(ownerID: UUID) {
        guard authorizedOwnerID == nil else { return }
        authorizedOwnerID = ownerID
    }

    func commitImportedPrefill(_ prefill: OilAnalysisImportPrefill, ownerID: UUID) {
        guard authorizedOwnerID == ownerID else { return }
        editableFields.apply(prefill)
        authorizedOwnerID = nil
    }

    func abortAuthorizedImport(ownerID: UUID) {
        guard authorizedOwnerID == ownerID else { return }
        authorizedOwnerID = nil
    }
}

struct EntryFormScaffold<Content: View>: View {
    let title: String
    @Bindable var viewModel: EntryFormViewModel
    var onSave: () async -> Bool
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
        mutationGate: (any EntryFormMutationGating)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _viewModel = Bindable(wrappedValue: viewModel)
        self.onSave = onSave
        self.mutationGate = mutationGate
        self.content = content()
    }

    var body: some View {
        BottomSheet(title: title) {
            DateOdometerHeader(
                entryDate: guardedBinding($viewModel.entryDate),
                odometerReading: guardedBinding($viewModel.odometerReading),
                lastKnownOdometer: viewModel.lastKnownOdometer
            )
            .disabled(isMutationLocked)
            content
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
            // One-shot: only the form opened straight from voice capture sees a pending prefill.
            if let prefill = router.consumeVoicePrefill() {
                viewModel.applyVoicePrefill(prefill)
            }
        }
    }

    private var isMutationLocked: Bool {
        mutationGate?.isMutationLocked ?? false
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
        router.dismissSheet()
    }

    /// Only surfaces the banner when the failed save is otherwise unexplained (no viewModel
    /// error already latched) and the vehicle really is gone — never masks a real save error.
    private func flagMissingVehicleIfNeeded() {
        guard viewModel.error == nil, appState.currentVehicle == nil else { return }
        noVehicleError = .validation("Select a vehicle first")
    }
}
