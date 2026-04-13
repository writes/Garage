import SwiftUI

struct ExportView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ExportViewModel()

    var body: some View {
        BottomSheet(title: "Export History") {
            if !appState.isPro {
                ProGateView(
                    title: "Exports are part of Pro",
                    message: "Generate buyer-ready PDF reports and full-fidelity CSV exports from one place."
                ) {
                    router.present(.subscription)
                }
            } else if let vehicle = appState.currentVehicle {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text("Report builder")
                        .font(Theme.Typography.title)
                    DatePicker("Start date", selection: $viewModel.startDate, displayedComponents: .date)
                    DatePicker("End date", selection: $viewModel.endDate, displayedComponents: .date)
                    Toggle("Include gallery photos", isOn: $viewModel.includeGalleryPhotos)
                    Toggle("Include receipts and invoices", isOn: $viewModel.includeReceipts)
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
                    }
                }
                .garageCard()

                PrimaryButton(title: "Build PDF Report") {
                    Task { await viewModel.buildPDF(vehicle: vehicle) }
                }
                SecondaryButton(title: "Build CSV Export") {
                    Task { await viewModel.buildCSV(vehicle: vehicle) }
                }
                if let data = viewModel.exportData {
                    Text("Export ready: \(data.count.formatted()) bytes")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
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
