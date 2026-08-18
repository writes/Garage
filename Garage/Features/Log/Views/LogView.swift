import SwiftUI

struct LogView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var viewModel = LogViewModel()
    @State private var entryService = EntryService.shared
    @State private var selectedEntry: FirestoreEntry?
    @State private var isShowingFilters = false
    @State private var entryPendingDeletion: FirestoreEntry?
    @State private var deletionError: AppError?

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.md) {
                SearchBar(text: $viewModel.searchText, placeholder: "Search notes, types, and details")

                if viewModel.isLoading || isAwaitingFirstLoad {
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
                    // A List (not ScrollView+LazyVStack, per the audit's swipe-to-delete ask):
                    // .swipeActions only exists on List rows. listRow* modifiers below strip the
                    // default List chrome so rows keep EntryRowView's own .garageCard() look.
                    List {
                        ForEach(viewModel.entries) { entry in
                            Button {
                                selectedEntry = entry
                            } label: {
                                if DesignPackStore.shared.pack.structure.usesUnderhoodPresentation {
                                    LogbookEntryRow(entry: entry)
                                } else {
                                    EntryRowView(entry: entry)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("log.row.\(entry.id)")
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) {
                                    entryPendingDeletion = entry
                                }
                                .accessibilityIdentifier("log.delete.\(entry.id)")
                            }
                        }
                        loadMoreFooter
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.bottom, Theme.Spacing.xxl, for: .scrollContent)
                }
            }
            .padding(Theme.Spacing.md)
            // Underhood-only paint: control's List kept the system background before this wave,
            // and the control baseline is pinned — Color.clear is the identity-stable no-op.
            .background(
                (DesignPackStore.shared.pack.structure.usesUnderhoodPresentation
                    ? Theme.Colors.background : Color.clear)
                    .ignoresSafeArea()
            )
            // In-stack chrome: "Log" in control, "Logbook" in Underhood, plus the §2.3 settings
            // accessory (control's flag is off, so its bar is untouched).
            .designTabRootChrome(for: .log)
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
                NavigationStack { EntryDetailView(entry: entry, entryService: entryService) }
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
            // The entry-detail sheet's own Delete dismisses it (selectedEntry -> nil); reload()
            // is revision-gated, so this is a no-op unless something actually changed.
            .onChange(of: selectedEntry) { _, newValue in
                guard newValue == nil else { return }
                Task { await reload() }
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: Binding(
                    get: { entryPendingDeletion != nil },
                    set: { if !$0 { entryPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Entry", role: .destructive) {
                    guard let entry = entryPendingDeletion else { return }
                    entryPendingDeletion = nil
                    Task { await delete(entry) }
                }
                Button("Cancel", role: .cancel) { entryPendingDeletion = nil }
            } message: {
                Text("This permanently deletes this record. This cannot be undone.")
            }
            .alert(
                "Could Not Delete Entry",
                isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
            ) {
                Button("OK", role: .cancel) { deletionError = nil }
            } message: {
                Text(deletionError?.errorDescription ?? "Please try again.")
            }
        }
    }

    private func delete(_ entry: FirestoreEntry) async {
        do {
            try await entryService.deleteEntry(entry, updatingVehicle: appState.currentVehicle)
            await reload()
        } catch {
            deletionError = AppError(from: error)
        }
    }

    /// The tab is built on first selection, so the frame between appearing and the first page
    /// landing is real. It must read as loading, not as "No log entries yet".
    ///
    /// Two gates, the same tri-state pair DashboardView resolves: entries cannot be loading until
    /// a vehicle exists to load them for, and "no vehicle" only means something once the vehicle
    /// load has actually completed. A CONFIRMED zero-vehicle account is the one case where the
    /// empty state is the honest answer.
    private var isAwaitingFirstLoad: Bool {
        guard appState.hasCompletedInitialVehicleLoad else { return true }
        guard let vehicle = appState.currentVehicle else { return false }
        return !viewModel.hasCompletedFirstLoad(for: vehicle.id)
    }

    /// A search or type filter narrows `entries` below `allEntries`; the footer caption and
    /// button read differently in that case since "Load More" fetches older raw history, not
    /// more filtered matches.
    private var isFiltering: Bool {
        !viewModel.searchText.isEmpty || !viewModel.selectedTypes.isEmpty
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if viewModel.allEntries.count >= Constants.maxLogEntries || viewModel.hasMoreEntries {
            VStack(spacing: Theme.Spacing.sm) {
                Text(isFiltering
                    ? "\(viewModel.entries.count) matching of the most recent \(viewModel.allEntries.count) entries"
                    : "Showing the most recent \(viewModel.allEntries.count) entries")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                if viewModel.hasMoreEntries {
                    Button(isFiltering ? "Search Older Entries" : "Load More") {
                        Task { await viewModel.loadMore() }
                    }
                    .disabled(viewModel.isLoadingMore)
                    .accessibilityIdentifier("log.loadMore")
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
    }

    private func reload() async {
        guard let vehicleId = appState.currentVehicle?.id else { return }
        await viewModel.reload(vehicleId: vehicleId)
    }
}
