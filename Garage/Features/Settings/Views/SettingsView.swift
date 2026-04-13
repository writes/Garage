import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Vehicles") { VehicleListView() }
                NavigationLink("Profile") { UserProfileView() }
                NavigationLink("Reminder Settings") { ReminderConfigView() }
                Button("Export History") { router.present(.export) }
                Button(appState.isPro ? "Manage Subscription" : "Upgrade to Pro") { router.present(.subscription) }
                Button("Sign Out") { try? AuthService.shared.signOut() }
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
