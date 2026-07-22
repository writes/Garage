import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var showDeleteConfirmation = false
    @State private var deletionError: AppError?
    @State private var isDeleting = false
    private let deletionService: any AccountDeleting = AccountDeletionService.shared

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Vehicles") { VehicleListView() }
                    .accessibilityIdentifier("settings.vehicles")
                NavigationLink("Profile") { UserProfileView() }
                    .accessibilityIdentifier("settings.profile")
                NavigationLink("Reminder Settings") { ReminderConfigView() }
                    .accessibilityIdentifier("settings.reminders")
                NavigationLink("Theme") { ThemePickerView() }
                    .accessibilityIdentifier("settings.theme")
                Button("Export History") { router.present(.export) }
                    .accessibilityIdentifier("settings.export")
                Button(appState.isPro ? "Manage Subscription" : "Upgrade to Pro") {
                    router.present(.subscription(.settings))
                }
                    .accessibilityIdentifier("settings.subscription")
                Button("Sign Out") { appState.signOut() }
                    .accessibilityIdentifier("settings.signout")
                Button(isDeleting ? "Deleting..." : "Delete Account", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isDeleting)
                .accessibilityIdentifier("settings.deleteAccount")
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
            .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) { Task { await deleteAccount() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This permanently deletes your account and every vehicle, log, photo, and "
                        + "record. This cannot be undone."
                )
            }
            .alert(
                "Couldn't delete account",
                isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deletionError?.errorDescription ?? "Please try again.")
            }
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            if !AppRuntime.isLocalDemoMode {
                try await deletionService.deleteAccount()
            }
            appState.signOut()
        } catch {
            deletionError = AppError(from: error)
        }
    }
}
