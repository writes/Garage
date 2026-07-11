import SwiftUI

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ExportViewModel()

    var body: some View {
        BottomSheet(title: "Export History") {
            if let vehicle = appState.currentVehicle {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Raw data export — free forever")
                        .font(Theme.Typography.title)
                    Text("Download this vehicle's complete history as a raw CSV file.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    SecondaryButton(title: "Build CSV Export") {
                        Task { await viewModel.buildCSV(vehicle: vehicle) }
                    }
                    .accessibilityIdentifier("export.buildCSV")
                    if let url = viewModel.csvExportURL {
                        ShareLink(item: url) {
                            Label("Share CSV Export", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("export.shareCSV")
                    }
                }
                .garageCard()

                // WAVE-3: PDF reports remain a Pro entitlement.
                if appState.isPro {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Report builder")
                            .font(Theme.Typography.title)
                        DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                            .accessibilityIdentifier("export.range.start")
                        DatePicker("End date", selection: $viewModel.endDate, displayedComponents: .date)
                            .accessibilityIdentifier("export.range.end")
                        Toggle("Include gallery photos", isOn: $viewModel.includeGalleryPhotos)
                            .accessibilityIdentifier("export.toggle.galleryPhotos")
                        Toggle("Include receipts and invoices", isOn: $viewModel.includeReceipts)
                            .accessibilityIdentifier("export.toggle.receipts")
                    }
                    .garageCard()

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Sections")
                            .font(Theme.Typography.headline)
                        ForEach(ReportSection.allCases) { section in
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

                    PrimaryButton(title: "Build PDF Report") {
                        Task { await viewModel.buildPDF(vehicle: vehicle) }
                    }
                    .accessibilityIdentifier("export.buildPDF")
                } else {
                    ProGateView(
                        title: "PDF reports are part of Pro",
                        message: "Upgrade to generate PDF report exports.",
                        actionIdentifier: "export.gate.cta"
                    ) {
                        router.present(.subscription(.exportPDF))
                    }
                }

                if let data = viewModel.exportData {
                    Text("PDF report ready: \(data.count.formatted()) bytes")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("export.pdfResult")
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
    }
}
