import SwiftUI

/// The mic sheet: dictate a service in one sentence, Garage drafts it, then routes to the entry
/// form prefilled for the user to confirm. Voice is Pro-gated; free users see an upgrade path.
struct VoiceQuickAddView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppState.self) private var appState
    @State private var viewModel = VoiceQuickAddViewModel()

    var body: some View {
        BottomSheet(title: "Speak an Entry") {
            if appState.isPro {
                proContent
            } else {
                upsell
            }
        }
        .onChange(of: viewModel.proposal) { _, _ in
            if let ready = viewModel.consumeProposal() {
                router.presentVoicePrefilledForm(ready)
            }
        }
    }

    private var proContent: some View {
        VStack(spacing: Theme.Spacing.lg) {
            micButton
            statusView
            if !viewModel.transcript.isEmpty {
                Text(viewModel.transcript)
                    .font(Theme.Typography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.sm)
                    .background(Theme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .accessibilityIdentifier("voice.transcript")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Spacing.md)
    }

    private var micButton: some View {
        Button {
            Task { await viewModel.toggle(vehicle: appState.currentVehicle) }
        } label: {
            Image(systemName: viewModel.isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.Colors.onPrimary)
                .frame(width: 96, height: 96)
                .background(viewModel.isListening ? Theme.Colors.error : Theme.Colors.primary)
                .clipShape(Circle())
                .shadow(color: .garageShadow, radius: 10, x: 0, y: 8)
        }
        .disabled(viewModel.phase == .thinking)
        .accessibilityIdentifier("voice.mic")
        .accessibilityLabel(viewModel.isListening ? "Stop recording" : "Start recording")
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.phase {
        case .idle:
            Text("Tap the mic and describe your service — for example, "
                + "“Oil change on the Viper at 18,120 miles, Mobil 1, did it myself.”")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        case .listening:
            Text("Listening… tap to finish.")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.primary)
        case .thinking:
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                Text("Drafting your entry…").font(Theme.Typography.body)
            }
            .accessibilityElement(children: .combine)
        case .failed(let failure):
            failureView(failure)
        }
    }

    @ViewBuilder
    private func failureView(_ failure: VoiceFailure) -> some View {
        switch failure {
        case .proRequired:
            upsell
        case .dailyExhausted(let resetAt):
            ErrorBanner(error: .unknown("You've used today's voice entries. Resets "
                + Self.resetText(resetAt) + "."))
                .accessibilityIdentifier("voice.error")
        case .permissionDenied:
            failureText("Enable Microphone and Speech Recognition in Settings to use voice entry.")
        case .recognizerUnavailable:
            failureText("Speech recognition isn't available right now. Please try again in a moment.")
        case .audioInputUnavailable:
            failureText("The microphone isn't available. Close anything else using it, then try again.")
        case .emptyTranscript:
            failureText("I didn't catch that. Tap the mic and try again.")
        case .generic(let message):
            ErrorBanner(error: .unknown(message)).accessibilityIdentifier("voice.error")
        }
    }

    private func failureText(_ message: String) -> some View {
        Text(message)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .accessibilityIdentifier("voice.error")
    }

    private var upsell: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Speak an Entry is a Pro feature")
                .font(Theme.Typography.headline)
            Text("Describe any service out loud and Garage drafts the log for you to confirm.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            PrimaryButton(title: "Upgrade to Pro") {
                router.present(.subscription(.voiceQuickAdd))
            }
            .accessibilityIdentifier("voice.upgrade")
        }
    }

    private static func resetText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
