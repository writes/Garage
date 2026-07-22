import Foundation

@MainActor
protocol OilAnalysisCalling: AnyObject {
    func parseOilAnalysis(pdfBase64: String, now: Date) async throws -> OilAnalysisEntry
}

enum OilAnalysisCallableError: Error, Equatable, Sendable {
    case freeLifetimeExhausted
    case proDailyExhausted(resetAt: Date)
}

struct OilAnalysisPDFConsentRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let displayFilename: String
}

@MainActor
protocol OilAnalysisPrefillApplying: AnyObject {
    func beginAuthorizedImport(ownerID: UUID)
    func commitImportedPrefill(_ prefill: OilAnalysisImportPrefill, ownerID: UUID)
    func abortAuthorizedImport(ownerID: UUID)
}

enum OilAnalysisPDFPreflightError: Error, Equatable, Sendable {
    case invalidFile
    case unreadableFile
    case fileTooLarge
    case invalidPDF

    var appError: AppError {
        switch self {
        case .unreadableFile:
            return .unknown("Couldn't read that PDF. Please choose it again.")
        case .invalidFile, .invalidPDF:
            return .validation("Choose a valid PDF oil-analysis report.")
        case .fileTooLarge:
            return .validation("Choose a PDF smaller than 6.75 MiB.")
        }
    }
}

@MainActor
protocol OilAnalysisPDFPreflighting: Sendable {
    func preflight(url: URL) async throws -> String
}

@MainActor
protocol OilAnalysisPDFSecurityScopeAccessing: Sendable {
    func acquire(for url: URL) -> Bool
    func release(for url: URL)
}

@MainActor
final class OilAnalysisPDFSecurityScopeLease {
    let url: URL
    private let access: any OilAnalysisPDFSecurityScopeAccessing
    private var didRelease = false
    init?(url: URL, access: any OilAnalysisPDFSecurityScopeAccessing) {
        guard access.acquire(for: url) else { return nil }
        self.url = url; self.access = access
    }
    func release() { guard !didRelease else { return }; didRelease = true; access.release(for: url) }
}

/// Security-scope access is intentionally owned by OilAnalysisImportCoordinator. The preflighter
/// has no access dependency and therefore cannot acquire or read a document before consent.
@MainActor
struct URLSecurityScopeAccess: OilAnalysisPDFSecurityScopeAccessing {
    func acquire(for url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func release(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

@MainActor
enum OilAnalysisImportState {
    case idle
    case picking(UUID)
    case pending(OilAnalysisPendingImport)
    case importing(OilAnalysisActiveImport)
    case cancelling(OilAnalysisActiveImport)
    case quarantined(OilAnalysisActiveImport)

    var allowsPicker: Bool {
        if case .idle = self { return true }
        return false
    }

    var allowsSave: Bool {
        switch self {
        case .idle:
            true
        case .picking, .pending, .importing, .cancelling, .quarantined:
            false
        }
    }
}

@MainActor
struct OilAnalysisPendingImport {
    let requestID: UUID
    let url: URL
    let displayFilename: String
    let lease: OilAnalysisPDFSecurityScopeLease

    var consent: OilAnalysisPDFConsentRequest {
        .init(id: requestID, displayFilename: displayFilename)
    }
}

@MainActor
final class OilAnalysisActiveImport {
    let ownerID: UUID
    let requestID: UUID
    let resultEpoch: UInt64
    let url: URL
    let clientIsPro: Bool
    let lease: OilAnalysisPDFSecurityScopeLease
    var importTask: Task<Void, Never>?
    var watchdogTask: Task<Void, Never>?

    init(
        ownerID: UUID,
        requestID: UUID,
        resultEpoch: UInt64,
        url: URL,
        clientIsPro: Bool,
        lease: OilAnalysisPDFSecurityScopeLease
    ) {
        self.ownerID = ownerID
        self.requestID = requestID
        self.resultEpoch = resultEpoch
        self.url = url
        self.clientIsPro = clientIsPro
        self.lease = lease
    }
}

actor OilAnalysisImportStartGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

struct OilAnalysisPDFPreflighter: OilAnalysisPDFPreflighting {
    /// Leaves callable JSON-envelope headroom below Firebase's 10 MiB request limit.
    nonisolated static let maxPDFBase64Bytes = 9 * 1024 * 1024
    /// Exactly 3 * floor(maxPDFBase64Bytes / 4): 7,077,888 source bytes.
    nonisolated static let maxRawBytes = 3 * (maxPDFBase64Bytes / 4)
    nonisolated private static let readChunkSize = 64 * 1024
    nonisolated private static let pdfMagic = Data("%PDF-".utf8)

    @MainActor
    func preflight(url: URL) async throws -> String {
        try Task.checkCancellation()
        let worker = Task.detached(priority: nil) { @Sendable () throws -> String in
            try Task.checkCancellation()
            return try Self.readValidatedBase64(from: url)
        }
        return try await withTaskCancellationHandler(operation: {
            try await worker.value
        }, onCancel: {
            worker.cancel()
        })
    }

    nonisolated static func readValidatedBase64(from url: URL) throws -> String {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw OilAnalysisPDFPreflightError.unreadableFile
        }
        guard values.isRegularFile == true else {
            throw OilAnalysisPDFPreflightError.invalidFile
        }
        if let metadataSize = values.fileSize, metadataSize > Self.maxRawBytes {
            throw OilAnalysisPDFPreflightError.fileTooLarge
        }
        return try readBoundedBase64(from: url)
    }

    nonisolated static func readBoundedBase64(from url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw OilAnalysisPDFPreflightError.unreadableFile
        }
        defer { try? handle.close() }
        var data = Data()
        while true {
            try Task.checkCancellation()
            let chunk: Data
            do {
                guard let read = try handle.read(upToCount: Self.readChunkSize), !read.isEmpty else {
                    break
                }
                chunk = read
            } catch {
                throw OilAnalysisPDFPreflightError.unreadableFile
            }
            guard data.count <= Self.maxRawBytes - chunk.count else {
                throw OilAnalysisPDFPreflightError.fileTooLarge
            }
            data.append(chunk)
        }
        try Task.checkCancellation()
        guard data.count <= Self.maxRawBytes else {
            throw OilAnalysisPDFPreflightError.fileTooLarge
        }
        guard data.starts(with: Self.pdfMagic) else {
            throw OilAnalysisPDFPreflightError.invalidPDF
        }
        let base64 = data.base64EncodedString()
        try Self.validateEncodedLength(base64)
        return base64
    }

    nonisolated static func validateEncodedLength(
        _ base64: String,
        maximum: Int = maxPDFBase64Bytes
    ) throws {
        guard base64.utf8.count <= maximum else {
            throw OilAnalysisPDFPreflightError.fileTooLarge
        }
    }
}
