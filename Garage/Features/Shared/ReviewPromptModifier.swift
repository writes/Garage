import StoreKit
import SwiftUI

/// Performs the StoreKit rating request when `ReviewPromptStore` says one is due.
///
/// Attached once at the app root rather than at each earning site, so the moment that earned the
/// prompt (saving an entry, finishing an export) does not have to also own presenting it — and a
/// sheet dismissing itself cannot take the request down with it.
private struct ReviewPromptModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    let store: ReviewPromptStore

    func body(content: Content) -> some View {
        content.task(id: store.isPromptDue) {
            guard store.isPromptDue else { return }

            // Let whatever produced the moment finish dismissing. A review alert raised while a
            // sheet is still animating away is dropped by the system with no error and no retry —
            // which silently burns one of the three prompts allowed per year.
            try? await Task.sleep(for: .seconds(1.5))

            // The user may have backgrounded the app during that wait; a request delivered to an
            // inactive scene is the same silent loss.
            guard !Task.isCancelled, scenePhase == .active, store.isPromptDue else { return }

            store.markPrompted()
            requestReview()
        }
    }
}

extension View {
    func reviewPrompt(_ store: ReviewPromptStore) -> some View {
        modifier(ReviewPromptModifier(store: store))
    }
}
