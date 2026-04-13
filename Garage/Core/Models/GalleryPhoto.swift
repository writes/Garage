import Foundation

struct GalleryPhoto: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var vehicleId: String
    var title: String
    var caption: String?
    var storagePath: String
    var shotDate: Date?
    var includeInExport: Bool
    var displayOrder: Int
    var section: GallerySection
    var wheelBrand: String?
    var wheelModel: String?
    var wheelSize: String?
    var wheelFinish: String?
    var tireComboAtTimeOfPhoto: String?
}

enum GallerySection: String, Codable, CaseIterable, Sendable {
    case main
    case wheel
}
