import Foundation

struct Attachment: Codable, Identifiable, Sendable, Equatable {
    enum AttachmentKind: String, Codable, Sendable {
        case receipt
        case photo
        case pdf
        case glamour
        case report
    }

    var id: String
    var storagePath: String
    var downloadURL: String?
    var filename: String
    var kind: AttachmentKind
    var createdAt: Date?
}
