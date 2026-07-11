import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Vehicles") { VehicleListView() }
                    .accessibilityIdentifier("settings.vehicles")
                NavigationLink("Profile") { UserProfileView() }
                    .accessibilityIdentifier("settings.profile")
                NavigationLink("Reminder Settings") { ReminderConfigView() }
                    .accessibilityIdentifier("settings.reminders")
                Button("Export History") { router.present(.export) }
                    .accessibilityIdentifier("settings.export")
                Button(appState.isPro ? "Manage Subscription" : "Upgrade to Pro") { router.present(.subscription) }
                    .accessibilityIdentifier("settings.subscription")
                Button("Sign Out") { appState.signOut() }
                    .accessibilityIdentifier("settings.signout")
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VehicleSwitcher()
                }
            }
        }
    }
}
