import SwiftUI

struct ErrorBanner: View {
    let error: AppError
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Something needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.error)

            Text(error.localizedDescription)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)

            if let retry {
                Button("Try Again", action: retry)
                    .font(Theme.Typography.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.error.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}
