import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @State private var showDeleteConfirmation = false
    @State private var deletionError: AppError?
    @State private var isDeleting = false
    @State private var isShowingManageSubscriptions = false
    // Computed (not a stored default) so the singleton — which calls Functions.functions() — is
    // constructed only when deletion actually runs, never at tab-build time. In demo/UI-test mode
    // Firebase is not configured, and deleteAccount() never touches it, so it must stay lazy.
    private var deletionService: any AccountDeleting { AccountDeletionService.shared }

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
                    manageSubscriptionTapped()
                }
                    .accessibilityIdentifier("settings.subscription")
                    // The persistent Settings upsell affordance is the impressions denominator
                    // for the `settings` conversion source; Pro users see "Manage", not an
                    // upsell, so no exposure fires for them.
                    .onAppear {
                        if !appState.isPro {
                            AnalyticsService.shared.track(.upsellExposure(source: .settings))
                        }
                    }
                if ExperimentStore.shared.isSurveyAvailable(for: .designMegatest) {
                    Button("Design Feedback") { router.present(.designSurvey) }
                        .accessibilityIdentifier("settings.designSurvey")
                }
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
            .manageSubscriptionsSheet(isPresented: $isShowingManageSubscriptions)
        }
    }

    /// Active Pro subscribers get StoreKit's real management sheet (cancel, change plan, billing
    /// history) instead of being re-shown the acquisition paywall. Demo/UI-test Pro is simulated
    /// (PurchaseService.uiTest — no real subscription behind it), so StoreKit has nothing to
    /// manage there; it keeps the existing paywall-sheet fallback instead of calling into StoreKit.
    private func manageSubscriptionTapped() {
        guard appState.isPro, !AppRuntime.isLocalDemoMode else {
            router.present(.subscription(.settings))
            return
        }
        isShowingManageSubscriptions = true
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let deletedUID = appState.currentUserID
            if !AppRuntime.isLocalDemoMode {
                try await deletionService.deleteAccount()
            }
            // Purchase-adjacent local state for a uid that no longer exists — retain nothing.
            if let deletedUID {
                ReceiptCreditsMarkerStore.shared.removeAll(uid: deletedUID)
            }
            appState.signOut()
        } catch {
            deletionError = AppError(from: error)
        }
    }
}
