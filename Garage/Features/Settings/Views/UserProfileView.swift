import SwiftUI

struct UserProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        Form {
            TextField("Name", text: $viewModel.name).accessibilityIdentifier("profile.name")
            TextField("Address", text: $viewModel.address).accessibilityIdentifier("profile.address")
            TextField("Phone", text: $viewModel.phone).accessibilityIdentifier("profile.phone")
            TextField("Insurance Company", text: $viewModel.insuranceCompany)
                .accessibilityIdentifier("profile.insurance")
            TextField("Policy Number", text: $viewModel.policyNumber)
                .accessibilityIdentifier("profile.policy")
            Toggle("Share anonymous usage analytics", isOn: Binding(
                get: { !viewModel.analyticsOptOut },
                set: { enabled in
                    Task {
                        guard await viewModel.setAnalyticsSharingEnabled(enabled),
                              let profile = viewModel.userProfile else { return }
                        appState.applyProfile(profile)
                    }
                }
            ))
            .accessibilityIdentifier("profile.analytics")
            .disabled(!viewModel.hasSuccessfullyLoadedProfile)
            if let error = viewModel.error {
                ErrorBanner(error: error)
                    .accessibilityIdentifier("profile.error")
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            Button("Save") {
                Task {
                    guard await viewModel.save(), let profile = viewModel.userProfile else { return }
                    appState.applyProfile(profile)
                }
            }
            .accessibilityIdentifier("profile.save")
        }
    }
}
