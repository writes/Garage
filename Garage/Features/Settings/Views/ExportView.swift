import SwiftUI

struct ExportSessionAuthorization: Equatable, Sendable {
    let authenticationRevision: Int
    let subscriptionRevision: UInt64
    let vehicleID: String
    let vehicleOwnerID: String

    static func resolve(
        authenticationRevision: Int,
        subscriptionRevision: UInt64,
        authenticatedUserID: String?,
        currentVehicle: Vehicle?,
        requestedVehicle: Vehicle
    ) -> Self? {
        guard let authenticatedUserID,
              requestedVehicle.userId == authenticatedUserID,
              currentVehicle?.id == requestedVehicle.id,
              currentVehicle?.userId == authenticatedUserID else { return nil }
        return .init(
            authenticationRevision: authenticationRevision,
            subscriptionRevision: subscriptionRevision,
            vehicleID: requestedVehicle.id,
            vehicleOwnerID: authenticatedUserID
        )
    }
}

struct PDFExportAuthorization: Equatable, Sendable {
    let session: ExportSessionAuthorization
}

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ExportViewModel()

    var body: some View {
        BottomSheet(title: "Export History") {
            if let vehicle = appState.currentVehicle {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("CSV record-data export")
                        .font(Theme.Typography.title)
                    Text(
                        "This CSV contains this vehicle's record history only. " +
                            "Photo and receipt files are not included."
                    )
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    SecondaryButton(title: "Build CSV Export") {
                        Task {
                            await viewModel.buildCSV(
                                vehicle: vehicle,
                                authorization: { exportSession(for: vehicle) }
                            )
                        }
                    }
                    .disabled(viewModel.isExporting)
                    .accessibilityIdentifier("export.buildCSV")
                    if let url = viewModel.authorizedCSVURL(for: exportSession(for: vehicle)) {
                        ShareLink(item: url) {
                            Label("Share CSV Export", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export.shareCSV")
                    }
                }
                .garageCard()

                // WAVE-3: Record PDF generation remains a Pro entitlement.
                if appState.isPro {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Record PDF")
                            .font(Theme.Typography.title)
                        Text("This record-only PDF does not include photo, receipt, or invoice files.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                            .accessibilityIdentifier("export.range.start")
                        DatePicker("End date", selection: $viewModel.endDate, displayedComponents: .date)
                            .accessibilityIdentifier("export.range.end")
                    }
                    .garageCard()

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Sections")
                            .font(Theme.Typography.headline)
                        ForEach(viewModel.recordPDFSections) { section in
                            Toggle(section.rawValue, isOn: Binding(
                                get: { viewModel.selectedSections.contains(section) },
                                set: { isOn in
                                    if isOn {
                                        viewModel.selectedSections.insert(section)
                                    } else {
                                        viewModel.selectedSections.remove(section)
                                    }
                                }
                            ))
                            .accessibilityIdentifier("export.toggle.\(section.id)")
                        }
                    }
                    .garageCard()

                    PrimaryButton(title: "Generate Record PDF") {
                        Task {
                            await viewModel.buildPDF(
                                vehicle: vehicle,
                                authorization: { pdfAuthorization(for: vehicle) }
                            )
                        }
                    }
                    .disabled(viewModel.isExporting)
                    .accessibilityIdentifier("export.buildPDF")
                } else {
                    ProGateView(
                        title: "Record PDF is part of Pro",
                        message: "Upgrade to generate a record PDF. Photo, receipt, and invoice files " +
                            "are not included.",
                        actionIdentifier: "export.gate.cta"
                    ) {
                        router.present(.subscription(.exportPDF))
                    }
                }

                if let url = viewModel.authorizedPDFURL(for: pdfAuthorization(for: vehicle)) {
                    ShareLink(item: url) {
                        Label("Share Record PDF", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("export.sharePDF")
                }
                if let error = viewModel.error {
                    ErrorBanner(error: error)
                }
            } else {
                EmptyStateView(
                    title: "Add a vehicle first",
                    message: "Exports are created per vehicle.",
                    systemImage: "car"
                )
            }
        }
        .onChange(of: currentExportSession, initial: true) { _, session in
            viewModel.sessionChanged(to: session)
        }
        .onDisappear {
            viewModel.discardExportArtifacts()
        }
    }

    private var currentExportSession: ExportSessionAuthorization? {
        guard let vehicle = appState.currentVehicle else { return nil }
        return exportSession(for: vehicle)
    }

    private func exportSession(for vehicle: Vehicle) -> ExportSessionAuthorization? {
        guard appState.isAuthenticated else { return nil }
        return ExportSessionAuthorization.resolve(
            authenticationRevision: appState.authenticationStateID,
            subscriptionRevision: appState.purchaseService.accountRevision,
            authenticatedUserID: activeUserID,
            currentVehicle: appState.currentVehicle,
            requestedVehicle: vehicle
        )
    }

    private var activeUserID: String? {
        if AppRuntime.isLocalDemoMode { return AppRuntime.demoUserId }
        return AuthService.shared.uid
    }

    private func pdfAuthorization(for vehicle: Vehicle) -> PDFExportAuthorization? {
        guard appState.isPro, let session = exportSession(for: vehicle) else { return nil }
        return PDFExportAuthorization(session: session)
    }
}
