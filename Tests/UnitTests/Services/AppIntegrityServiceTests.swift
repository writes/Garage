import Testing
@testable import Garage

struct AppIntegrityServiceTests {
    @Test func providerSelection_usesDebugProviderOnDebugSimulator() {
        #expect(
            AppIntegrityService.providerSelection(
                isDebug: true,
                isSimulator: true,
                debugToken: nil
            ) == .debug
        )
    }

    @Test func providerSelection_usesDebugProviderOnDebugDeviceWithToken() {
        #expect(
            AppIntegrityService.providerSelection(
                isDebug: true,
                isSimulator: false,
                debugToken: "debug-token"
            ) == .debug
        )
    }

    @Test func providerSelection_usesDeviceProviderWithoutDebugConditions() {
        #expect(
            AppIntegrityService.providerSelection(
                isDebug: true,
                isSimulator: false,
                debugToken: nil
            ) == .device
        )
        #expect(
            AppIntegrityService.providerSelection(
                isDebug: false,
                isSimulator: true,
                debugToken: "debug-token"
            ) == .device
        )
    }
}
