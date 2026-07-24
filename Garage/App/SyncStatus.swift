import Foundation

// Split out of AppState.swift to stay under the file cap (mirrors EntryServiceDeletionTests'
// precedent for test files) — a fully self-contained type with no dependency on AppState's
// private internals.
enum SyncStatus: String, Sendable {
    case idle
    case upToDate
    case syncing
    case offline
    case attentionNeeded

    var label: String {
        switch self {
        case .idle: return "Up to date"
        case .upToDate: return "Up to date"
        case .syncing: return "Syncing"
        case .offline: return "Offline"
        case .attentionNeeded: return "Needs attention"
        }
    }
}
