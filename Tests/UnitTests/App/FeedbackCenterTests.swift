import Testing
@testable import Garage

/// The haptic itself is not observable from a test, so what is pinned here is the only part that
/// can silently break: the counter semantics `.sensoryFeedback(trigger:)` depends on. A trigger
/// that repeats a value does not fire, and a shared trigger across kinds fires the wrong feedback.
@MainActor
struct FeedbackCenterTests {
    @Test func countersStartAtZeroSoNothingFiresOnFirstRender() {
        let center = FeedbackCenter()
        #expect(center.count(for: .success) == 0)
        #expect(center.count(for: .warning) == 0)
        #expect(center.count(for: .lightImpact) == 0)
    }

    @Test func fireIncrementsOnlyTheRequestedKind() {
        let center = FeedbackCenter()
        center.fire(.success)
        #expect(center.count(for: .success) == 1)
        #expect(center.count(for: .warning) == 0)
        #expect(center.count(for: .lightImpact) == 0)

        center.fire(.lightImpact)
        #expect(center.count(for: .success) == 1)
        #expect(center.count(for: .lightImpact) == 1)

        center.fire(.warning)
        #expect(center.count(for: .warning) == 1)
        #expect(center.count(for: .success) == 1)
        #expect(center.count(for: .lightImpact) == 1)
    }

    /// The reason this is a counter rather than a Bool or a re-assigned enum: saving two entries
    /// in a row must produce two DISTINCT trigger values, or the second save is silent.
    @Test func repeatedFiresOfOneKindEachProduceANewTriggerValue() {
        let center = FeedbackCenter()
        var seen: [Int] = []
        for _ in 0..<5 {
            center.fire(.success)
            seen.append(center.count(for: .success))
        }
        #expect(seen == [1, 2, 3, 4, 5])
        #expect(Set(seen).count == 5)
    }

    @Test func kindsAdvanceIndependently() {
        let center = FeedbackCenter()
        center.fire(.lightImpact)
        center.fire(.lightImpact)
        center.fire(.lightImpact)
        center.fire(.success)
        #expect(center.count(for: .lightImpact) == 3)
        #expect(center.count(for: .success) == 1)
        #expect(center.count(for: .warning) == 0)
    }

    /// The emitters call `FeedbackCenter.shared`, so the singleton must be the same instance the
    /// ContentView observer holds — a fresh instance per access would observe nothing.
    @Test func sharedIsASingleInstance() {
        let before = FeedbackCenter.shared.count(for: .success)
        FeedbackCenter.shared.fire(.success)
        #expect(FeedbackCenter.shared.count(for: .success) == before + 1)
    }
}
