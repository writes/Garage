import Foundation

/// Domain vocabulary handed to the speech recogniser as `contextualStrings`.
///
/// `SFSpeechRecognizer` biases toward general English, and the words this app most needs are the
/// ones it is worst at: brand names, part names, and units. "Mobil 1" comes back as "mobile one",
/// "rotors" as "routers", "Michelin" as "Michelle in". Every one of those lands in the transcript
/// that the extraction model then has to interpret, so a recognition error becomes a wrong field —
/// and the fix belongs here, before the transcript exists, not in a prompt afterwards.
///
/// Deliberately not exhaustive. Apple treats these as hints and the list competes with itself:
/// hundreds of terms dilute the bias rather than sharpen it, so this stays at the vocabulary a
/// maintenance sentence actually uses, plus whatever the user's own vehicle is called.
enum SpeechVocabulary {
    /// Terms common to any maintenance sentence.
    static let automotive: [String] = [
        // Units and readings — these carry the numbers, so mis-hearing them loses the value.
        "odometer", "mileage", "miles", "quarts", "litres", "PSI", "torque",
        // Services, in the words owners actually say.
        "oil change", "oil filter", "air filter", "cabin filter", "spark plugs",
        "brake pads", "rotors", "brake fluid", "coolant flush", "transmission fluid",
        "tire rotation", "wheel alignment", "tread depth", "serpentine belt", "timing belt",
        "differential", "drivetrain", "suspension", "shocks", "struts", "alternator",
        // Oil weights, which recognisers routinely mangle into words.
        "0W-20", "0W-40", "5W-20", "5W-30", "5W-40", "10W-30", "10W-40",
        // Brands that appear on receipts and in speech.
        "Mobil 1", "Castrol", "Liqui Moly", "Valvoline", "Pennzoil", "Amsoil",
        "Michelin", "Bridgestone", "Continental", "Pirelli", "Goodyear", "Falken",
        "Brembo", "Akebono", "Bosch", "Denso", "Blackstone"
    ]

    /// The user's own vehicle, which is the single most likely proper noun in the sentence and the
    /// one no generic list can contain.
    static func terms(for vehicle: Vehicle?) -> [String] {
        guard let vehicle else { return automotive }
        let specifics = [
            vehicle.make,
            vehicle.model,
            "\(vehicle.make) \(vehicle.model)",
            vehicle.nickname
        ]
        .map { $0.trimmed }
        .filter { !$0.isEmpty }

        // Ordered vehicle-first: when a recogniser weighs hints, the words unique to this user
        // should outrank the generic list they share with everyone.
        var seen = Set<String>()
        return (specifics + automotive).filter { seen.insert($0.lowercased()).inserted }
    }
}
