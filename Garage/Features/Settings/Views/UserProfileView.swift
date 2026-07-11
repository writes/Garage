import SwiftUI

struct UserProfileView: View {
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
        }
        .navigationTitle("Profile")
        .toolbar {
            Button("Save") {
                Task { await viewModel.save() }
            }
            .accessibilityIdentifier("profile.save")
        }
    }
}
