import Observation

@MainActor
@Observable
final class ProfileViewModel {
    var name = ""
    var address = ""
    var phone = ""
    var insuranceCompany = ""
    var policyNumber = ""
}
