import Foundation
import Testing
@testable import Garage

/// Architecture test for the offline-write contract documented in `LocalFirstWrite.swift`.
///
/// This defect class is invisible to behavioural tests. `try await ref.setData(…)` resolves only
/// on SERVER acknowledgement, and the Firestore boundary cannot be faked from a unit test, so an
/// ack-gated write is indistinguishable from a local-first one at every seam above it — the hang
/// only exists against the real backend, offline. The single place the difference IS observable is
/// the source, so that is what this checks. Three real hangs shipped behind that blind spot with
/// green unit tests: reminder completion, profile writes, and vehicle edit.
@MainActor
struct OfflineWriteContractTests {
    /// Firestore's awaited overloads. `.delete()` is matched with its parens closed so that domain
    /// calls like `await reminderService.delete(reminder)` are not mistaken for a document delete.
    private static let ackGatedCalls = [".setData(", ".updateData(", ".commit(", ".delete()"]

    /// Awaited writes that SHOULD wait. Each entry is a decision with a reason, not a suppression.
    private static let justifiedAckGatedWrites: Set<String> = [
        // RULES-1 counted create: the server is the authority on the vehicle cap, so the
        // permission verdict on this batch is the entire point of making the call.
        "VehicleService+CountedCreate.swift|try await batch.commit()",
        // Firebase Storage, not Firestore. Storage has no offline queue, so there is no local
        // write to fall back on and awaiting is correct (LocalFirstWrite.swift says so explicitly).
        "EntryAttachmentService.swift|try await root.child(path).delete()"
    ]

    private struct ScanResult {
        var offenders: [String] = []
        var scannedFileCount = 0
    }

    private static var garageSourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // UnitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("Garage")
    }

    private static func scan(_ root: URL) throws -> ScanResult {
        var result = ScanResult()
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result.scannedFileCount += 1
            let source = try String(contentsOf: url, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                let statement = line.trimmingCharacters(in: .whitespaces)
                guard !statement.hasPrefix("//"), statement.contains("await") else { continue }
                guard ackGatedCalls.contains(where: statement.contains) else { continue }
                let signature = "\(url.lastPathComponent)|\(statement)"
                guard !justifiedAckGatedWrites.contains(signature) else { continue }
                result.offenders.append(signature)
            }
        }
        return result
    }

    private static func source(of fileName: String) throws -> String {
        let enumerator = FileManager.default.enumerator(at: garageSourceRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.lastPathComponent == fileName else { continue }
            return try String(contentsOf: url, encoding: .utf8)
        }
        return ""
    }

    // MARK: - Defect 1: completing a reminder hung forever offline

    /// Marking a reminder done awaited the server, and BOTH side effects were sequenced after that
    /// await — so offline the spinner never stopped, the stale local notification was never
    /// cancelled, and a repeating reminder silently lost its next occurrence for good.
    @Test func reminderCompletionWriteIsLocalFirst() throws {
        let source = try Self.source(of: "ReminderService.swift")
        #expect(!source.isEmpty)
        #expect(source.contains("context: \"reminder completion\""))
        let scan = try Self.scan(Self.garageSourceRoot.appendingPathComponent("Core/Services/Domain"))
        #expect(scan.offenders.filter { $0.hasPrefix("ReminderService.swift|") }.isEmpty)
    }

    // MARK: - Defect 2: profile writes hung forever offline

    /// Name/address/insurance, the analytics-consent toggle and the accent theme all wrote through
    /// this one seam. Theme was the sharp one: it flips `AccentStore` BEFORE the write, so an
    /// ack-gated write left the UI wearing a colour that was never persisted and put the rollback
    /// behind a suspension that never resumed. The seam is non-`async` precisely so the awaited
    /// overload cannot be selected here again.
    @Test func profileDocumentSeamIsLocalFirstAndNonAsync() throws {
        let source = try Self.source(of: "FirestoreService.swift")
        #expect(!source.isEmpty)
        #expect(!source.contains("merge: Bool) async throws"))
        #expect(source.contains("context: \"profile\""))
    }

    // MARK: - The whole app

    @Test func noUnjustifiedAckGatedFirestoreWritesRemain() throws {
        #expect(FileManager.default.fileExists(atPath: Self.garageSourceRoot.path))
        let scan = try Self.scan(Self.garageSourceRoot)
        // A path change must fail this test loudly rather than pass it by scanning nothing.
        #expect(scan.scannedFileCount > 100)
        #expect(scan.offenders == [], "Ack-gated Firestore writes hang offline; see LocalFirstWrite.swift")
    }
}
