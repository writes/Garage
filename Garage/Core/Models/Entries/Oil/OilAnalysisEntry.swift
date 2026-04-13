import Foundation

struct OilAnalysisEntry: Codable, Sendable, Equatable {
    var labName: String
    var pdfPath: String?
    var aluminum: Double?
    var chromium: Double?
    var iron: Double?
    var copper: Double?
    var lead: Double?
    var tin: Double?
    var molybdenum: Double?
    var nickel: Double?
    var manganese: Double?
    var silver: Double?
    var titanium: Double?
    var silicon: Double?
    var sodium: Double?
    var potassium: Double?
    var viscosity: String?
    var insolubles: Double?
    var milesOnOil: Int?
    var labRecommendation: String?
}
