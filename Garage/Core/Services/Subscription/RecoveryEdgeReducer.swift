enum NetworkPathVerdict: Equatable, Sendable {
    case satisfied
    case unsatisfied
    case unknown
}

enum RecoveryEdgeReducer {
    static func isReconnectEdge(
        previous: NetworkPathVerdict?,
        new: NetworkPathVerdict
    ) -> Bool {
        switch (previous, new) {
        case (.unsatisfied?, .satisfied), (.unknown?, .satisfied):
            return true
        default:
            return false
        }
    }
}
