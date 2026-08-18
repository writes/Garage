import SwiftUI

struct EntryTypePicker: View {
    @Environment(AppRouter.self) private var router

    private var framing: DesignFraming {
        DesignPackStore.shared.pack.structure.framing
    }

    var body: some View {
        BottomSheet(title: framing.recordTitle ?? "New Entry") {
            if let subtitle = framing.recordSubtitle {
                Text(subtitle)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            Button {
                router.present(.voiceQuickAdd)
            } label: {
                Label("Speak an Entry", systemImage: "mic.fill")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            .accessibilityIdentifier("entry.picker.voice")
            // Demo/UI-test mode has no real callable/Storage backing this row (G3) — same
            // reasoning as EntryFormScaffold's attachmentsSection hide.
            if !AppRuntime.isLocalDemoMode {
                Button {
                    router.present(.receiptCapture)
                } label: {
                    Label("Scan a Receipt", systemImage: "doc.text.viewfinder")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .accessibilityIdentifier("entry.picker.receipt")
            }
            Divider()
            ForEach(EntryType.allCases, id: \.self) { entryType in
                Button {
                    router.present(.entryForm(entryType))
                } label: {
                    Label(entryType.displayName, systemImage: entryType.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.sm)
                }
                .accessibilityIdentifier("entry.picker.\(entryType.rawValue)")
            }
        }
    }
}
