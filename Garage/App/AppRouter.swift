import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Sheet: Identifiable, Equatable {
        case entryPicker
        case entryForm(EntryType)
        case vehicleForm
        case export
        case subscription(PaywallSource)

        var id: String {
            switch self {
            case .entryPicker: return "entryPicker"
            case .entryForm(let type): return "entryForm-\(type.rawValue)"
            case .vehicleForm: return "vehicleForm"
            case .export: return "export"
            case .subscription(let source): return "subscription-\(source.rawValue)"
            }
        }
    }

    var activeSheet: Sheet?

    func present(_ sheet: Sheet) {
        activeSheet = sheet
    }

    func dismissSheet() {
        activeSheet = nil
    }
}
