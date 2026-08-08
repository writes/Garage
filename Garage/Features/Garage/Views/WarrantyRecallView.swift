import SwiftUI

struct WarrantyRecallView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = WarrantyViewModel()
    @State private var sheet: AddSheet?

    var body: some View {
        List {
            if isAwaitingLoad {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("garage.warranty.loading")
            }
            // One banner above both sections: it carries the load failures this screen used to
            // swallow AND the `.validation` errors checkForRecalls sets ("Add this vehicle's VIN…"),
            // which had no rendering path at all — the NHTSA button simply appeared to do nothing.
            if let error = viewModel.error {
                ErrorBanner(error: error) {
                    Task { await load() }
                }
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("garage.warranty.error")
            }

            Section("Warranties") {
                if !viewModel.warranties.isEmpty {
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
                } else if showsEmptyPlaceholders {
                    Text("No warranty records yet")
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
                if !viewModel.recalls.isEmpty {
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
                } else if showsEmptyPlaceholders {
                    Text("No recall records yet")
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

    /// See DetailingLogView.isAwaitingLoad: a selected vehicle whose first fetch has not resolved
    /// is loading, not empty.
    private var isAwaitingLoad: Bool {
        guard let vehicle = appState.currentVehicle else { return viewModel.isLoading }
        return viewModel.isLoading || !viewModel.hasCompletedFirstLoad(for: vehicle.id)
    }

    /// "No … records yet" is a claim about the account's data, so it is only made once a load has
    /// resolved cleanly. While one is in flight, or while the banner is reporting a failure, the
    /// sections stay silent rather than asserting an emptiness nobody has confirmed.
    private var showsEmptyPlaceholders: Bool {
        !isAwaitingLoad && viewModel.error == nil
    }

    private func load() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.load(vehicleId: vehicleId)
    }
}
