import Foundation
import Observation

@MainActor
@Observable
final class VehicleFormViewModel {
    private let vehicleService: VehicleService
    private let analytics: any AnalyticsTracking

    var nickname = ""
    var make = ""
    var model = ""
    var year = String(Calendar.current.component(.year, from: Date.now))
    var currentOdometer = ""
    var fuelType: FuelType = .premium93
    private(set) var error: AppError?

    init(
        vehicleService: VehicleService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.vehicleService = vehicleService
        self.analytics = analytics
    }

    func save() async -> Bool {
        guard Validators.nonEmpty(nickname, fieldName: "Nickname") == nil else {
            error = .validation("Nickname is required.")
            return false
        }
        guard Validators.nonEmpty(make, fieldName: "Make") == nil else {
            error = .validation("Make is required.")
            return false
        }
        guard Validators.nonEmpty(model, fieldName: "Model") == nil else {
            error = .validation("Model is required.")
            return false
        }
        guard Validators.positiveInteger(currentOdometer, fieldName: "Odometer") == nil else {
            error = .validation("Current odometer is required.")
            return false
        }

        do {
            let vehicle = Vehicle(
                id: UUID().uuidString,
                userId: "",
                nickname: nickname,
                make: make,
                model: model,
                year: Int(year) ?? Calendar.current.component(.year, from: Date.now),
                currentOdometer: Int(currentOdometer) ?? 0,
                fuelType: fuelType,
                displayOrder: 0
            )
            _ = try await vehicleService.createVehicle(vehicle)
            if let vehicles = try? await vehicleService.fetchVehicles(), vehicles.count == 1 {
                analytics.track(.firstVehicleAdded)
            }
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }
}
