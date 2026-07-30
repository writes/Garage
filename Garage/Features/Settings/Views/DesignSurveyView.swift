import SwiftUI

/// The 3-question design-megatest survey. At review-phase cohort sizes, structured
/// within-subject preference is worth more than underpowered between-subject conversion
/// deltas (plan §3) — this sheet is that instrument. Answers are two 1–5 scores and one
/// yes/no; no free text can exist here, matching the analytics contract's structural
/// no-strings rule.
struct DesignSurveyView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var easeScore = 3
    @State private var visualScore = 3
    @State private var wouldSwitch = false
    @State private var didSubmit = false

    private let analytics: any AnalyticsTracking
    private let experiments: ExperimentStore

    init(
        analytics: any AnalyticsTracking = AnalyticsService.shared,
        experiments: ExperimentStore = .shared
    ) {
        self.analytics = analytics
        self.experiments = experiments
    }

    var body: some View {
        BottomSheet(title: "Design Feedback") {
            scoreQuestion(
                "How easy is the app to use day to day?",
                score: $easeScore,
                identifier: "survey.ease"
            )
            scoreQuestion(
                "How does the design look to you?",
                score: $visualScore,
                identifier: "survey.visual"
            )

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Would you switch to a different look if offered?")
                    .font(Theme.Typography.headline)
                Toggle("I'd switch", isOn: $wouldSwitch)
                    .accessibilityIdentifier("survey.wouldSwitch")
            }
            .garageCard()

            PrimaryButton(title: "Send Feedback") {
                // Rapid double-tap while the sheet animates away must not double-count.
                guard !didSubmit else { return }
                didSubmit = true
                analytics.track(.surveySubmitted(
                    survey: .designMegatest,
                    easeScore: easeScore,
                    visualScore: visualScore,
                    wouldSwitch: wouldSwitch
                ))
                experiments.markSurveySubmitted(for: .designMegatest)
                dismiss()
            }
            .accessibilityIdentifier("survey.submit")
        }
        .onDisappear {
            // A close without submit is a real funnel signal (survey fatigue vs engagement);
            // fired from onDisappear so the swipe-down dismissal counts too.
            if !didSubmit {
                analytics.track(.surveyDismissed(survey: .designMegatest))
            }
        }
    }

    @ViewBuilder
    private func scoreQuestion(_ prompt: String, score: Binding<Int>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(prompt)
                .font(Theme.Typography.headline)
            Picker(prompt, selection: score) {
                ForEach(1...5, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(identifier)
            HStack {
                Text("Not great").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("Excellent").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .garageCard()
    }
}
