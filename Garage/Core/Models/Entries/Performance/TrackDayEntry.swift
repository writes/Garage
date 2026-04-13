import Foundation

struct TrackDayEntry: Codable, Sendable, Equatable {
    var venueName: String
    var eventType: TrackEventType
    var runGroup: String?
    var numberOfLaps: Int?
    var bestLapTime: String?
    var conditions: TrackConditions
    var tireSetId: String?
    var fuelUsedGallons: Double?
    var carObservations: String?
    var driverNotes: String?
    var heatCyclesAdded: Int
}

enum TrackEventType: String, Codable, CaseIterable, Sendable {
    case hpde
    case timeTrial
    case lapping
    case race
}

enum TrackConditions: String, Codable, CaseIterable, Sendable {
    case dry
    case wet
    case mixed
}
