import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Garage")
                    .font(Theme.Typography.largeTitle)
                Text("Keep a clear manual service and maintenance history for your car.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SignInWithAppleButton(.signIn) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task {
                    await viewModel.handleAppleCompletion(result)
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)
            .disabled(viewModel.isLoading)

            if let simulatorHelpText = AuthViewModel.simulatorHelpText {
                Text(simulatorHelpText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Continue with Google") {
                Task {
                    await viewModel.signInWithGoogle()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("login.googleButton")

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let error = viewModel.error {
                ErrorBanner(error: error)
            }

            Text(
                "Sign in to sync service-log records. Offline entries send when Garage reconnects "
                    + "while open or after it is reopened."
            )
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
