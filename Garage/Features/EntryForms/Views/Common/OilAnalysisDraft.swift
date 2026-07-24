import Foundation
import Observation
import SwiftUI

// MARK: - Oil-analysis draft + mutation-gating machinery (split out of EntryFormScaffold.swift to
// stay under its file cap; EntryFormScaffold.mutationGate: (any EntryFormMutationGating)? is the
// only cross-file reference, and OilAnalysisFormView is this protocol's only conformer's user).

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
