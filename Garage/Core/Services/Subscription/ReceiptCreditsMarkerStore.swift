import Foundation
import Observation

/// Persisted, per-uid, TRANSACTION-ID-KEYED queue of purchases whose server grant has not
/// reached a terminal state — plus the Q3-C paywall-dismissal flag. A single slot would let a
/// second purchase overwrite a still-delayed first (Sol-final-4); each marker resolves
/// independently. Markers expire 72h after purchase: a deterministic provenance rejection
/// would otherwise re-poll forever on every sheet open, and a wire-visible "foreign" state was
/// rejected as an existence oracle — expiry is client-local (Gemini-r5).
///
/// Same persistence pattern as ReviewPromptStore/ExperimentStore: one versioned JSON blob,
/// `nil` defaults = in-memory (tests/demo/UI-test), corrupt data discarded.
@MainActor
@Observable
final class ReceiptCreditsMarkerStore {
    struct Marker: Codable, Equatable, Sendable {
        let transactionID: String
        let purchasedAtMillis: Int
    }

    static let markerTTL: TimeInterval = 72 * 60 * 60
    private static let storageKey = "garage.receipt-credits.v1"

    static let shared = ReceiptCreditsMarkerStore(
        defaults: AppRuntime.isLocalDemoMode || AppRuntime.isUITestMode ? nil : .standard
    )

    private struct State: Codable, Equatable {
        var markersByUID: [String: [Marker]] = [:]
        var paywallDismissedUIDs: [String] = []
        /// UIDs with a marker that hit TTL still unresolved — backs the durable support notice.
        /// Optional so blobs persisted before this field existed still decode (a required key
        /// would trip the corrupt-discard path and silently drop every account's repair queue).
        var expiredUnresolvedUIDs: [String]?
    }

    private let defaults: UserDefaults?
    private var state = State()

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let data = defaults?.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        }
    }

    // MARK: - Markers

    func add(transactionID: String, uid: String, now: Date) {
        var markers = state.markersByUID[uid] ?? []
        guard !markers.contains(where: { $0.transactionID == transactionID }) else { return }
        markers.append(Marker(transactionID: transactionID, purchasedAtMillis: Int(now.timeIntervalSince1970 * 1000)))
        state.markersByUID[uid] = markers
        persist()
    }

    /// PURE read: the uid's markers split by TTL. Expired markers are NOT pruned here — the
    /// caller owes each one a final status/reconcile before declaring it lost; pruning on read
    /// destroyed the repair key before that attempt could happen (tri-review Sol blocker).
    func unexpiredMarkers(uid: String, now: Date) -> (active: [Marker], expired: [Marker]) {
        let markers = state.markersByUID[uid] ?? []
        let cutoff = now.timeIntervalSince1970 * 1000 - Self.markerTTL * 1000
        return (
            active: markers.filter { Double($0.purchasedAtMillis) >= cutoff },
            expired: markers.filter { Double($0.purchasedAtMillis) < cutoff }
        )
    }

    /// Terminal (`granted`/`refunded`) — the marker's job is done.
    func resolve(transactionID: String, uid: String) {
        remove(transactionID: transactionID, uid: uid)
    }

    /// Terminal MISS: the final post-TTL reconcile still found nothing. The marker is destroyed
    /// but the uid keeps a durable support flag — silent expiry would let a charged user be
    /// re-offered another pack with no explanation surviving a sheet reopen.
    func markExpiredUnresolved(transactionID: String, uid: String) {
        var flagged = state.expiredUnresolvedUIDs ?? []
        if !flagged.contains(uid) { flagged.append(uid) }
        state.expiredUnresolvedUIDs = flagged
        remove(transactionID: transactionID, uid: uid)
    }

    func hasExpiredUnresolvedPurchase(uid: String) -> Bool {
        state.expiredUnresolvedUIDs?.contains(uid) == true
    }

    private func remove(transactionID: String, uid: String) {
        guard var markers = state.markersByUID[uid] else { return }
        markers.removeAll { $0.transactionID == transactionID }
        state.markersByUID[uid] = markers.isEmpty ? nil : markers
        persist()
    }

    // MARK: - Q3-C paywall-dismissal flag

    func recordPaywallDismissed(uid: String) {
        guard !state.paywallDismissedUIDs.contains(uid) else { return }
        state.paywallDismissedUIDs.append(uid)
        persist()
    }

    func hasDismissedPaywall(uid: String) -> Bool {
        state.paywallDismissedUIDs.contains(uid)
    }

    /// Account deletion: markers and the dismissal flag are purchase-adjacent state for a uid
    /// that no longer exists — retain nothing (tri-review hygiene finding). Plain sign-out
    /// deliberately KEEPS them (multi-account devices resume their own markers on return).
    func removeAll(uid: String) {
        state.markersByUID.removeValue(forKey: uid)
        state.paywallDismissedUIDs.removeAll { $0 == uid }
        state.expiredUnresolvedUIDs?.removeAll { $0 == uid }
        persist()
    }

    private func persist() {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
