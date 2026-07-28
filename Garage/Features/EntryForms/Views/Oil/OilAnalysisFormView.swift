import Observation
import SwiftUI
import UniformTypeIdentifiers

struct OilAnalysisFormView: View {
    private enum FocusedField: Hashable { case labName, viscosity, milesOnOil, iron, aluminum, recommendation }
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var form = EntryFormViewModel()
    @State private var draft: OilAnalysisDraft
    @State private var importCoordinator: OilAnalysisImportCoordinator
    @State private var isImportingPDF = false
    @State private var pickerSessionID: UUID?
    @FocusState private var focusedField: FocusedField?
    init() {
        let draft = OilAnalysisDraft()
        _draft = State(initialValue: draft)
        _importCoordinator = State(initialValue: OilAnalysisImportCoordinator(draftSink: draft))
    }
    var body: some View {
        EntryFormScaffold(
            title: "Oil Analysis",
            viewModel: form,
            onSave: save,
            onEditEntry: seed,
            mutationGate: importCoordinator
        ) {
            importMutationSurface
            importOutcome
            if importCoordinator.canCancelActiveImport {
                Button("Cancel Import", role: .cancel) {
                    importCoordinator.cancelActiveImport()
                }
                .accessibilityIdentifier("oilAnalysis.cancelImport")
            } else if importCoordinator.isCancelling {
                Text("Cancelling import…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("oilAnalysis.cancellingImport")
            }
        }
        .onAppear { importCoordinator.sceneDidChange(isBackgrounded: scenePhase == .background) }
        .onChange(of: scenePhase) { _, phase in
            let isBackgrounded = phase == .background
            importCoordinator.sceneDidChange(isBackgrounded: isBackgrounded)
            guard isBackgrounded else { return }
            isImportingPDF = false; pickerSessionID = nil
        }
        .fileImporter(isPresented: $isImportingPDF, allowedContentTypes: [.pdf]) { result in
            let sessionID = pickerSessionID
            pickerSessionID = nil
            isImportingPDF = false
            guard let sessionID else { return }
            importCoordinator.completePicker(sessionID: sessionID, result: result, saveInProgress: form.isSaving)
        }
        .sheet(item: consentBinding) { request in
            OilAnalysisConsentSheet(
                request: request,
                isSaveInProgress: form.isSaving,
                send: {
                    focusedField = nil
                    return importCoordinator.confirmConsent(
                        requestID: request.id,
                        clientIsPro: appState.isPro,
                        saveInProgress: form.isSaving
                    )
                },
                cancel: {
                    importCoordinator.cancelPendingConsent(requestID: request.id)
                },
                disappeared: {
                    importCoordinator.schedulePassiveDismissal(requestID: request.id)
                }
            )
        }
        .onChange(of: importCoordinator.outcome) { _, outcome in
            if case .showPaywall = outcome {
                router.present(.subscription(.oilAnalysis))
            }
        }
        .onDisappear {
            importCoordinator.tearDown()
        }
    }
    private var consentBinding: Binding<OilAnalysisPDFConsentRequest?> {
        Binding(
            get: { importCoordinator.pendingConsent },
            set: { value in
                guard value == nil, let pending = importCoordinator.pendingConsent else { return }
                importCoordinator.schedulePassiveDismissal(requestID: pending.id)
            }
        )
    }
    private var importMutationSurface: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Button {
                guard let sessionID = importCoordinator.beginPicker(saveInProgress: form.isSaving) else {
                    return
                }
                pickerSessionID = sessionID
                isImportingPDF = true
            } label: {
                Label("Import Oil Analysis PDF", systemImage: "doc.fill")
            }
            .disabled(!importCoordinator.canBeginPicker || form.isSaving)
            .accessibilityIdentifier("oilAnalysis.importPDF")
            TextField("Lab name", text: draft.textBinding(\.labName, gate: importCoordinator))
                .focused($focusedField, equals: .labName).textFieldStyle(.roundedBorder)
            TextField("Viscosity", text: draft.textBinding(\.viscosity, gate: importCoordinator))
                .focused($focusedField, equals: .viscosity).textFieldStyle(.roundedBorder)
            TextField("Miles on oil", text: draft.textBinding(\.milesOnOil, gate: importCoordinator))
                .focused($focusedField, equals: .milesOnOil).keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
            TextField("Iron (ppm)", text: draft.textBinding(\.iron, gate: importCoordinator))
                .focused($focusedField, equals: .iron).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Aluminum (ppm)", text: draft.textBinding(\.aluminum, gate: importCoordinator))
                .focused($focusedField, equals: .aluminum).keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Lab recommendation", text: draft.textBinding(\.labRecommendation, gate: importCoordinator))
                .focused($focusedField, equals: .recommendation).textFieldStyle(.roundedBorder)
        }
        .disabled(importCoordinator.isMutationLocked)
    }
    @ViewBuilder
    private var importOutcome: some View {
        switch importCoordinator.outcome {
        case .idle, .prefill, .showPaywall:
            EmptyView()
        case .syncPending:
            Text("Your Pro purchase is still syncing. Please try again in a moment.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityIdentifier("oilAnalysis.syncPending")
        case .dailyQuota(let resetAt):
            ErrorBanner(error: .oilAnalysisDailyQuota(resetAt: resetAt))
                .accessibilityIdentifier("oilAnalysis.importError")
        case .inlineError(let error):
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("oilAnalysis.importError")
                if importCoordinator.needsCancellationRecovery {
                    Button("Resume Import Controls") {
                        importCoordinator.recoverFromQuarantinedCancellation()
                    }
                    .accessibilityIdentifier("oilAnalysis.recoverImport")
                }
            }
        }
    }
    /// Reuses the exact prefill machinery the PDF-import path already uses (OilAnalysisImportPrefill
    /// + OilAnalysisEditableFields.apply) — a direct mutation, not through the gated textBinding,
    /// since this runs once at initial load, never concurrently with a user edit or live import.
    private func seed(from entry: FirestoreEntry) {
        guard let details = entry.decodedDetails(as: OilAnalysisEntry.self) else { return }
        draft.editableFields.apply(OilAnalysisImportPrefill(entry: details))
    }
    private func save() async -> Bool {
        let admissionEpoch = importCoordinator.mutationEpoch
        guard importCoordinator.canCommitSave(epoch: admissionEpoch),
              let vehicle = appState.currentVehicle else {
            return false
        }
        let editableFields = draft.editableFields
        let details = OilAnalysisEntry(
            labName: editableFields.labName,
            pdfPath: nil,
            aluminum: Double(editableFields.aluminum),
            chromium: nil,
            iron: Double(editableFields.iron),
            copper: nil,
            lead: nil,
            tin: nil,
            molybdenum: nil,
            nickel: nil,
            manganese: nil,
            silver: nil,
            titanium: nil,
            silicon: nil,
            sodium: nil,
            potassium: nil,
            viscosity: editableFields.viscosity.isEmpty ? nil : editableFields.viscosity,
            insolubles: nil,
            milesOnOil: Int(editableFields.milesOnOil),
            labRecommendation: editableFields.labRecommendation.isEmpty ? nil : editableFields.labRecommendation
        )
        // The final main-actor check happens immediately before EntryFormViewModel persists.
        guard importCoordinator.canCommitSave(epoch: admissionEpoch) else { return false }
        return await form.save(vehicle: vehicle, entryType: .oilAnalysis, details: details)
    }
}

struct OilAnalysisConsentSheet: View {
    let request: OilAnalysisPDFConsentRequest
    let isSaveInProgress: Bool
    let send: () -> Bool
    let cancel: () -> Void
    let disappeared: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var didClaimAction = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Send oil-analysis PDF?")
                    .font(Theme.Typography.headline)
                Text(
                    "\(request.displayFilename) will be sent to Anthropic Claude to extract structured " +
                        "oil-analysis fields for this entry."
                )
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                Text("Send authorizes this document only. Cancel sends nothing.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
            .padding(Theme.Spacing.lg)
            .navigationTitle("PDF Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        guard !didClaimAction else { return }
                        didClaimAction = true
                        cancel()
                        dismiss()
                    }
                    .accessibilityIdentifier("oilAnalysis.consentCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        guard !didClaimAction else { return }
                        didClaimAction = true
                        guard send() else {
                            didClaimAction = false
                            return
                        }
                        dismiss()
                    }
                    .disabled(isSaveInProgress || didClaimAction)
                    .accessibilityIdentifier("oilAnalysis.consentSend")
                }
            }
        }
        .accessibilityIdentifier("oilAnalysis.consentSheet")
        .onDisappear(perform: disappeared)
    }
}
