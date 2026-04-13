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
                Text("Track everything that happens to your car without fighting the app.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SignInWithAppleButton(.signIn) { _ in
            } onCompletion: { _ in
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 54)

            Button("Continue with Google") {
                viewModel.showSetupMessage()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

            if let error = viewModel.error {
                ErrorBanner(error: error)
            }

            Text("No passwords. One account keeps your service history across devices.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
