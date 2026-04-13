import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.garage"

    static let shared = Logger(subsystem: subsystem, category: "general")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let purchase = Logger(subsystem: subsystem, category: "purchase")
    static let entries = Logger(subsystem: subsystem, category: "entries")
    static let sync = Logger(subsystem: subsystem, category: "sync")
}
