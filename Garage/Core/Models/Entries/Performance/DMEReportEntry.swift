import Foundation

struct DMEReportEntry: Codable, Sendable, Equatable {
    var providerName: String
    var reportPath: String?
    var reportType: DMEReportType
    var summary: String?
}

enum DMEReportType: String, Codable, CaseIterable, Sendable {
    case overRevs = "over_revs"
    case faultCodes = "fault_codes"
    case other
}
