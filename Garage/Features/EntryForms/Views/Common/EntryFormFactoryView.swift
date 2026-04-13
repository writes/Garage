import SwiftUI

struct EntryFormFactoryView: View {
    let entryType: EntryType

    var body: some View {
        switch entryType {
        case .oilChange: OilChangeFormView()
        case .oilConsumption: OilConsumptionFormView()
        case .oilAnalysis: OilAnalysisFormView()
        case .fuel: FuelFormView()
        case .tire: TireFormView()
        case .brake: BrakeFormView()
        case .alignment: AlignmentFormView()
        case .maintenance: MaintenanceFormView()
        case .repair: RepairFormView()
        case .trackDay: TrackDayFormView()
        case .upgrade: UpgradeFormView()
        case .dmeReport: DMEReportFormView()
        }
    }
}
