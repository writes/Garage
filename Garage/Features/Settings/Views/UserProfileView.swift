import SwiftUI

struct UserProfileView: View {
    @State private var viewModel = ProfileViewModel()

    var body: some View {
        Form {
            TextField("Name", text: $viewModel.name)
            TextField("Address", text: $viewModel.address)
            TextField("Phone", text: $viewModel.phone)
            TextField("Insurance Company", text: $viewModel.insuranceCompany)
            TextField("Policy Number", text: $viewModel.policyNumber)
        }
        .navigationTitle("Profile")
    }
}
