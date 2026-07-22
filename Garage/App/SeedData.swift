import Foundation

enum SeedData {
    static let vehicles: [Vehicle] = [
        Vehicle(
            id: "seed-viper",
            userId: "debug-user",
            nickname: "Viper ACR",
            make: "Dodge",
            model: "Viper ACR",
            year: 2008,
            currentOdometer: 18_240,
            fuelType: .premium93,
            color: "Red",
            displayOrder: 0
        ),
        Vehicle(
            id: "seed-sq5",
            userId: "debug-user",
            nickname: "Daily SQ5",
            make: "Audi",
            model: "SQ5",
            year: 2015,
            currentOdometer: 82_440,
            fuelType: .premium91,
            color: "Gray",
            displayOrder: 1
        )
    ]
}
