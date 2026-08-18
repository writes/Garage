import AuthenticationServices
import SwiftUI

extension DesignSignInWithAppleStyle {
    /// The AuthenticationServices button this token renders. The mapping lives HERE, beside its one
    /// consumer, so the design layer never has to import AuthenticationServices — and so a pack
    /// that commits to a dark world cannot be defeated by a hardcoded `.black` in the view.
    var buttonStyle: SignInWithAppleButton.Style {
        switch self {
        case .black: return .black
        case .white: return .white
        case .whiteOutline: return .whiteOutline
        }
    }
}

struct LoginView: View {
    @State private var viewModel = AuthViewModel()

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if DesignPackStore.shared.pack.structure.usesUnderhoodPresentation {
                    UnderhoodEyebrow(text: "Sign in to sync", accent: true)
                    Text("GARAGE")
                        .font(Theme.Typography.largeTitle)
                        .tracking(2)
                    Text("Your manual service history — clear, portable, and yours.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    Text("Garage")
                        .font(Theme.Typography.largeTitle)
                    Text("Keep a clear manual service and maintenance history for your car.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SignInWithAppleButton(.signIn) { request in
                viewModel.prepareAppleRequest(request)
            } onCompletion: { result in
                Task {
                    await viewModel.handleAppleCompletion(result)
                }
            }
            .signInWithAppleButtonStyle(
                DesignPackStore.shared.pack.components.signInWithApple.buttonStyle
            )
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
