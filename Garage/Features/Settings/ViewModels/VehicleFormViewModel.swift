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
    private(set) var isSaving = false

    init(
        vehicleService: VehicleService = .shared,
        analytics: any AnalyticsTracking = AnalyticsService.shared
    ) {
        self.vehicleService = vehicleService
        self.analytics = analytics
    }

    func save() async -> Bool {
        // Re-entrancy guard: a double-tap must not race the vehicle-count check into a duplicate.
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }

        if let validationError = firstValidationError() {
            error = validationError
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
            // This VM only ever creates — there is no edit branch — so every successful save
            // here is a new vehicle.
            if let vehicles = try? await vehicleService.fetchVehicles() {
                analytics.track(.vehicleAdded(vehicleCount: vehicles.count))
                if vehicles.count == 1 {
                    analytics.track(.firstVehicleAdded)
                }
            }
            error = nil
            return true
        } catch {
            self.error = AppError(from: error)
            return false
        }
    }

    private func firstValidationError() -> AppError? {
        if Validators.nonEmpty(nickname, fieldName: "Nickname") != nil {
            return .validation("Nickname is required.")
        }
        if Validators.nonEmpty(make, fieldName: "Make") != nil {
            return .validation("Make is required.")
        }
        if Validators.nonEmpty(model, fieldName: "Model") != nil {
            return .validation("Model is required.")
        }
        if Validators.positiveInteger(currentOdometer, fieldName: "Odometer") != nil {
            return .validation("Current odometer is required.")
        }
        return nil
    }
}
