import Foundation

/// The text of the resale dossier, derived from the vehicle and its entries.
///
/// Split from `PDFExportService` so the *content* — which is the product — can be tested without
/// TPPDF, a document, or a main actor. The renderer's only job becomes putting these lines on
/// pages.
///
/// ## What was wrong with the old dossier
///
/// It was close to a stub, which matters because the PDF is the paid artifact and the entire
/// resale pitch. Vehicle info printed the nickname and current odometer and nothing else — no
/// year, make, model or VIN, so the document did not identify the car it described. Each service
/// was one line of "Oil Change • 3 Mar 2026" plus free-text notes, with **no odometer reading**,
/// no cost and no shop. Mileage at each service is the single most important fact in a maintenance
/// history: "oil changed at 42,180 mi" is evidence, "oil changed in March" is an assertion. And
/// five sections the export screen offers — cost summary, wear summary, warranties, recalls,
/// detailing, spare parts — rendered nothing at all, so ticking them changed the document by zero
/// bytes.
enum DossierContent {
    struct Line: Equatable, Sendable {
        enum Style: Equatable, Sendable {
            case title
            case heading
            case body
            case caption
        }
        let style: Style
        let text: String
    }

    // MARK: - Vehicle identity

    /// A dossier that does not identify its vehicle is worthless to a buyer, which is what the
    /// nickname alone amounted to. Optional fields are omitted rather than printed as "unknown" —
    /// a gap the reader can see is more honest than a field asserting absence.
    static func vehicleLines(_ vehicle: Vehicle) -> [Line] {
        var lines: [Line] = [
            .init(style: .title, text: "\(vehicle.year) \(vehicle.make) \(vehicle.model)".trimmed)
        ]
        if vehicle.nickname.isNotEmpty, vehicle.nickname != vehicle.model {
            lines.append(.init(style: .caption, text: vehicle.nickname))
        }
        lines.append(.init(style: .body, text: "Odometer: \(vehicle.currentOdometer.formatted()) mi"))

        // VIN is what makes the document checkable against the car and the title, so it leads the
        // detail block when present.
        if let vin = vehicle.vin?.trimmed, vin.isNotEmpty {
            lines.append(.init(style: .body, text: "VIN: \(vin)"))
        }
        let details: [(String, String?)] = [
            ("Colour", vehicle.color?.trimmed),
            ("Plate", vehicle.licensePlate?.trimmed),
            ("Fuel", vehicle.fuelType?.displayName),
            ("Engine oil", vehicle.engineOilType?.trimmed),
            ("Tyres (front)", vehicle.tireSizeFront?.trimmed),
            ("Tyres (rear)", vehicle.tireSizeRear?.trimmed)
        ]
        for (label, value) in details where !(value ?? "").isEmpty {
            lines.append(.init(style: .body, text: "\(label): \(value ?? "")"))
        }
        if let purchased = vehicle.purchaseDate {
            let atMiles = vehicle.odometerAtPurchase.map { " at \($0.formatted()) mi" } ?? ""
            lines.append(.init(style: .body, text: "Owned since \(purchased.shortDisplay)\(atMiles)"))
        }
        return lines
    }

    // MARK: - Service records

    /// One line per service, carrying the four facts a buyer checks: what, when, **at what
    /// mileage**, and what it cost. Shop name or "DIY" follows, because who did the work is part of
    /// the record's credibility.
    static func entryLine(_ entry: FirestoreEntry) -> String {
        var parts = [entry.entryType.displayName, entry.entryDate.shortDisplay]
        if entry.odometerReading > 0 {
            parts.append("\(entry.odometerReading.formatted()) mi")
        }
        if let cost = entry.cost, cost > 0 {
            parts.append(cost.currencyText)
        }
        if let shop = entry.shopName?.trimmed, shop.isNotEmpty {
            parts.append(shop)
        } else if entry.isDiy == true {
            parts.append("DIY")
        }
        return parts.joined(separator: " · ")
    }

    /// Grouped under headings and newest-first within each group. The old export emitted one
    /// undifferentiated stream, so a reader could not find "every brake service" without reading
    /// the whole document — the exact task a resale dossier exists to make easy.
    static func historyGroups(
        entries: [FirestoreEntry], selectedSections: Set<ReportSection>
    ) -> [(section: ReportSection, entries: [FirestoreEntry])] {
        let grouped = Dictionary(grouping: entries) { section(for: $0.entryType) }
        return ReportSection.allCases.compactMap { section in
            guard selectedSections.contains(section), let group = grouped[section], !group.isEmpty else {
                return nil
            }
            return (section, group.sorted { $0.entryDate > $1.entryDate })
        }
    }

    /// The section an entry type belongs to. Mirrors the old `shouldInclude` switch exactly, so
    /// which entries a given selection includes is unchanged — only how they are arranged is.
    static func section(for type: EntryType) -> ReportSection {
        switch type {
        case .oilChange, .oilConsumption, .oilAnalysis: return .oilHistory
        case .fuel, .maintenance, .repair, .dmeReport: return .maintenanceHistory
        case .tire: return .tireHistory
        case .brake: return .brakeHistory
        case .alignment: return .alignmentRecords
        case .trackDay: return .trackDays
        case .upgrade: return .upgrades
        }
    }

    // MARK: - Summaries

    /// Reuses the calculator behind the Stats card so the figure a buyer reads and the figure the
    /// owner saw are the same number, derived once.
    static func costSummaryLines(entries: [FirestoreEntry], now: Date) -> [Line] {
        guard let summary = OwnershipCostCalculator.summary(for: entries, now: now) else { return [] }
        var lines: [Line] = [.init(style: .heading, text: ReportSection.costSummary.rawValue)]
        lines.append(.init(style: .body, text: "Total recorded spend: \(summary.totalCost.currencyText)"))
        if let perMile = summary.costPerMile {
            lines.append(.init(
                style: .body,
                text: "Cost per mile: \(perMile.currencyPerMileText) across "
                    + "\(summary.milesCovered.formatted()) logged miles"
            ))
        }
        if let perMonth = summary.costPerMonth {
            lines.append(.init(style: .body, text: "Average per month: \(perMonth.currencyText)"))
        }
        // Says what the figures rest on. A total drawn from six entries is a different claim from
        // one drawn from six hundred, and the reader cannot weigh it without the count.
        lines.append(.init(
            style: .caption,
            text: "Based on \(entries.count.formatted()) recorded entries."
        ))
        return lines
    }

    static func wearSummaryLines(_ items: [WearItem]) -> [Line] {
        guard !items.isEmpty else { return [] }
        var lines: [Line] = [.init(style: .heading, text: ReportSection.wearSummary.rawValue)]
        for item in items {
            let raw = item.rawValue.map { " (\($0))" } ?? ""
            lines.append(.init(
                style: .body,
                text: "\(item.type.label): \(Int(item.percentage.rounded()))% remaining\(raw)"
            ))
        }
        return lines
    }

    static func warrantyLines(_ warranties: [Warranty], now: Date) -> [Line] {
        guard !warranties.isEmpty else { return [] }
        var lines: [Line] = [.init(style: .heading, text: ReportSection.warranties.rawValue)]
        for warranty in warranties {
            let end = warranty.expirationDate ?? warranty.coverageEnd
            // "Expired" vs "active" is the fact a buyer is actually looking for, so it is stated
            // rather than left to be worked out from a date.
            let state = end.map { $0 >= now ? "active until \($0.shortDisplay)" : "expired \($0.shortDisplay)" }
                ?? "no end date recorded"
            let provider = warranty.providerName?.trimmed.nilIfEmpty ?? warranty.warrantyType.displayName
            var text = "\(provider): \(state)"
            if let limit = warranty.mileageLimit {
                text += ", to \(limit.formatted()) mi"
            }
            lines.append(.init(style: .body, text: text))
        }
        return lines
    }

    static func recallLines(_ recalls: [Recall]) -> [Line] {
        guard !recalls.isEmpty else { return [] }
        var lines: [Line] = [.init(style: .heading, text: ReportSection.recalls.rawValue)]
        for recall in recalls {
            let campaign = recall.campaignNumber?.trimmed.nilIfEmpty.map { " (\($0))" } ?? ""
            lines.append(.init(
                style: .body,
                text: "\(recall.title)\(campaign) — \(recall.status.displayName)"
            ))
        }
        return lines
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
