// Prints what this machine can do, so a test log says whether the unit tests ran with or
// without the on-device model. It asserts nothing: both answers are fine.

import FoundationModels
import Testing

@Suite("Environment")
struct EnvironmentTests {

    @Test("Report whether the on-device model is available")
    func reportModelAvailability() {
        print("[Environment] on-device model availability: \(SystemLanguageModel.default.availability)")
    }
}
