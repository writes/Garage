import SwiftUI

struct LogView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = LogViewModel()
    @State private var selectedEntry: FirestoreEntry?
    @State private var isShowingFilters = false

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                SearchBar(text: $viewModel.searchText, placeholder: "Search notes, types, and details")

                if viewModel.isLoading {
                    LoadingOverlay()
                } else if let error = viewModel.error {
                    ErrorBanner(error: error, retry: { Task { await reload() } })
                } else if viewModel.entries.isEmpty {
                    EmptyStateView(
                        title: "No log entries yet",
                        message: "Tap the add button to start your vehicle history.",
                        systemImage: "list.bullet.clipboard"
                    )
                } else {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.md) {
                            ForEach(viewModel.entries) { entry in
                                Button {
                                    selectedEntry = entry
                                } label: {
                                    EntryRowView(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("log.row.\(entry.id)")
                            }
                        }
                        .padding(.bottom, Theme.Spacing.xxl)
                    }
                }
            }
            .padding(Theme.Spacing.md)
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Filter") {
                        isShowingFilters = true
                    }
                    .accessibilityIdentifier("log.filter")
                }
            }
            .task(id: appState.currentVehicle?.id) { await reload() }
            .sheet(item: $selectedEntry) { entry in
                NavigationStack { EntryDetailView(entry: entry) }
            }
            .sheet(isPresented: $isShowingFilters) {
                EntryFilterSheet(selectedTypes: $viewModel.selectedTypes)
            }
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.applyFilter()
            }
            .onChange(of: viewModel.selectedTypes) { _, _ in
                viewModel.applyFilter()
            }
            .onChange(of: router.activeSheet) { _, activeSheet in
                guard activeSheet == nil else { return }
                Task { await reload() }
            }
        }
    }

    private func reload() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.reload(vehicleId: vehicleId)
    }
}
