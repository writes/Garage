import FirebaseFirestore
import Foundation

/// Firestore writes that must not wait for the server.
///
/// ## Why this exists rather than a comment repeated in eight services
///
/// Firestore ships two forms of every write:
///
/// ```
/// func setData(_ data: [String: Any], completion: ((Error?) -> Void)? = nil)  // local, returns now
/// func setData(_ data: [String: Any]) async throws                            // waits for SERVER ack
/// ```
///
/// Three things compound to make the wrong one the default:
///
/// 1. Inside an `async` function Swift silently prefers the async overload — so the obvious
///    `try await ref.setData(…)` is the one that never resumes while offline.
/// 2. Dropping the `await` does not compile; the compiler asks for it back.
/// 3. Passing an explicit completion does not compile either — Swift 6 rejects completion-handler
///    APIs called from an async context ("consider using asynchronous alternative function").
///
/// The compiler will not let you write the offline-safe call from an `async` function at all. The
/// only way out is a NON-async function, which is what these are. Calling one of these from an
/// async context is fine; calling `setData` directly from there is not.
///
/// For a car app this is not a nicety. Garages, underground parking and rural roads are exactly
/// where people log service, and an awaited write there hangs the UI forever — no error, no
/// timeout, nothing to retry. The write itself is never lost: Firestore persists it locally and
/// syncs on reconnect. Only the *waiting* was ever the problem.
///
/// Storage uploads are deliberately NOT routed through here. `StorageService.putDataAsync` and
/// attachment deletes are genuinely network-bound — Firebase Storage has no offline queue, so
/// awaiting them is correct.
extension FirestoreService {
    /// Persists locally and returns immediately; syncs when the device reconnects.
    /// `context` names the caller in the log so a sync failure is attributable.
    nonisolated func writeLocalFirst(
        _ data: [String: Any],
        to reference: DocumentReference,
        merge: Bool = true,
        context: String
    ) {
        reference.setData(data, merge: merge) { error in
            if let error {
                AppLogger.sync.error("\(context) sync failed: \(error.localizedDescription)")
            }
        }
    }

    /// Deletes locally and returns immediately. Firestore removes the document from the local
    /// cache at once, so listeners and reads reflect it before the server ever hears about it.
    nonisolated func deleteLocalFirst(_ reference: DocumentReference, context: String) {
        reference.delete { error in
            if let error {
                AppLogger.sync.error("\(context) delete sync failed: \(error.localizedDescription)")
            }
        }
    }
}
