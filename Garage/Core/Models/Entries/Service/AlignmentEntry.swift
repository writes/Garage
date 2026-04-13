import Foundation

struct AlignmentEntry: Codable, Sendable, Equatable {
    var shopNotes: String?
    var frontCaster: String?
    var alignmentSheetPath: String?
    var beforeSpecs: AlignmentSpecs
    var afterSpecs: AlignmentSpecs
}

struct AlignmentSpecs: Codable, Sendable, Equatable {
    var frontLeftCamber: String?
    var frontRightCamber: String?
    var rearLeftCamber: String?
    var rearRightCamber: String?
    var frontLeftToe: String?
    var frontRightToe: String?
    var rearLeftToe: String?
    var rearRightToe: String?
    var frontLeftCaster: String?
    var frontRightCaster: String?
}
