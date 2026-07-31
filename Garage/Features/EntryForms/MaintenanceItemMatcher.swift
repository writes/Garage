import Foundation

/// Maps the extraction's free-text `workItem` onto the maintenance form's item picker.
///
/// Deliberately conservative: keyword containment against a hand-curated table, no fuzzy
/// scoring. A miss returns nil and the picker keeps its default — a wrong confident match would
/// file the entry under the wrong service, which is worse than asking the user to pick
/// (documented rev-1 limitation: the picker default itself remains substantive, Sol #11/#12).
enum MaintenanceItemMatcher {
    /// Order matters only where keyword sets could overlap: more specific rows come first
    /// ("cabin air filter" must not fall through to "air filter", "brake fluid" must not
    /// reach the generic coolant row).
    private static let table: [(keywords: [String], item: MaintenanceItemKind)] = [
        (["cabin air filter", "cabin filter", "pollen filter"], .cabinAirFilter),
        (["brake fluid"], .brakeFluidFlush),
        (["air filter", "engine filter"], .airFilter),
        (["spark plug"], .sparkPlugs),
        (["wiper"], .wiperBlades),
        (["battery"], .batteryReplaced),
        (["coolant flush", "coolant"], .coolantFlush),
        (["radiator", "cooling system"], .radiatorCoolingSystem),
        (["transmission"], .transmissionService),
        (["differential", "diff service", "diff fluid"], .differentialService),
        (["belt", "hose"], .beltsAndHoses),
        (["fuel system", "fuel injector", "injector clean"], .fuelSystemService),
        (["rotate", "rotation", "balance"], .rotateBalanceTires)
    ]

    static func match(_ workItem: String) -> MaintenanceItemKind? {
        let lowered = workItem.lowercased()
        for row in table where row.keywords.contains(where: { lowered.contains($0) }) {
            return row.item
        }
        return nil
    }
}
