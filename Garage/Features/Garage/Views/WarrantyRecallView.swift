import SwiftUI

struct WarrantyRecallView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = WarrantyViewModel()
    @State private var sheet: AddSheet?

    var body: some View {
        List {
            Section("Warranties") {
                if viewModel.warranties.isEmpty {
                    Text("No warranty records yet")
                } else {
                    ForEach(viewModel.warranties) { warranty in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(warranty.warrantyType.displayName).font(Theme.Typography.headline)
                            Text(
                                warranty.expirationDate?.shortDisplay
                                    ?? warranty.coverageEnd?.shortDisplay
                                    ?? "No expiration date"
                            )
                                .font(Theme.Typography.caption)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section("Recalls") {
                // The lookup is free, keyless and safety-relevant, so it is NOT behind the Pro
                // fence — a recall the owner does not know about is the one thing in this app that
                // can hurt someone.
                Button {
                    guard let vehicle = appState.currentVehicle else { return }
                    Task { await viewModel.checkForRecalls(vehicle: vehicle) }
                } label: {
                    if viewModel.isCheckingRecalls {
                        Label("Checking NHTSA…", systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label("Check NHTSA for recalls", systemImage: "magnifyingglass")
                    }
                }
                .disabled(viewModel.isCheckingRecalls || appState.currentVehicle == nil)
                .accessibilityIdentifier("recall.check")

                if let summary = viewModel.lastRecallCheck {
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("recall.checkSummary")
                }
                if viewModel.recalls.isEmpty {
                    Text("No recall records yet")
                } else {
                    ForEach(viewModel.recalls) { recall in
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(recall.title).font(Theme.Typography.headline)
                            Text(recall.status.displayName).font(Theme.Typography.caption)
                                .foregroundStyle(
                                    recall.status == .outstanding
                                        ? Theme.Colors.error
                                        : Theme.Colors.textSecondary
                                )
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Warranty & Recalls")
        .task(id: appState.currentVehicle?.id) { await load() }
        // Weekly feature-usage matrix; warranty viewing has no other event.
        .onAppear { AnalyticsService.shared.track(.featureUsed(feature: .warranty)) }
        // Until now this screen had no way to create anything: WarrantyService's two save methods
        // had zero callers, so an advertised Pro feature could only ever be empty.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Warranty") { sheet = .warranty }
                    Button("Add Recall") { sheet = .recall }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .disabled(appState.currentVehicle == nil)
                .accessibilityIdentifier("warranty.add")
            }
        }
        .sheet(item: $sheet) { sheet in
            if let vehicleId = appState.currentVehicle?.id {
                switch sheet {
                case .warranty:
                    WarrantyFormView(vehicleId: vehicleId) { await viewModel.add($0) }
                case .recall:
                    RecallFormView(vehicleId: vehicleId) { await viewModel.add($0) }
                }
            }
        }
    }

    private enum AddSheet: String, Identifiable {
        case warranty
        case recall
        var id: String { rawValue }
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
