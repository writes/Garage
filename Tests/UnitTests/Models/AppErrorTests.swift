import Foundation
import Testing
@testable import Garage

struct AppErrorTests {
    @Test func networkNSError_mapsToNetwork() {
        let error = NSError(
            domain: NSURLErrorDomain,
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "Offline"]
        )

        #expect(AppError(from: error) == .network("Offline"))
    }
}
