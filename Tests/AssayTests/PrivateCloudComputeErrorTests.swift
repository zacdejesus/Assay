// Recording from Private Cloud Compute without its entitlement fails with an error that says
// nothing; the cassette translates it. The nesting below is the one seen on macOS 27.2.1 under
// `swift test` (LanguageModelError -1 → LanguageModelError -1 → ModelManagerError 1046).

@testable import Assay
import Foundation
import FoundationModels
import Testing

@Suite("Private Cloud Compute without the entitlement")
struct PrivateCloudComputeErrorTests {

    static func observedError(code: Int = 1046) -> NSError {
        let manager = NSError(domain: "ModelManagerServices.ModelManagerError", code: code,
                              userInfo: [NSMultipleUnderlyingErrorsKey: [NSError]()])
        let inner = NSError(domain: "FoundationModels.LanguageModelError", code: -1,
                            userInfo: [NSMultipleUnderlyingErrorsKey: [manager]])
        return NSError(domain: "FoundationModels.LanguageModelError", code: -1,
                       userInfo: [NSMultipleUnderlyingErrorsKey: [inner]])
    }

    static func recorder(pcc: Bool) -> Cassette.Recorder {
        Cassette.Recorder(capabilities: .init([]), isPrivateCloudCompute: pcc) { _ in LanguageModelSession() }
    }

    @Test("The nested ModelManagerError 1046 is recognized")
    func recognized() {
        #expect(Cassette.Recorder.isMissingPrivateCloudComputeEntitlement(Self.observedError()))
        let viaUnderlying = NSError(domain: "x", code: 1, userInfo: [
            NSUnderlyingErrorKey: NSError(domain: "ModelManagerServices.ModelManagerError", code: 1046),
        ])
        #expect(Cassette.Recorder.isMissingPrivateCloudComputeEntitlement(viaUnderlying))
    }

    @Test("Other errors are not")
    func otherErrors() {
        #expect(!Cassette.Recorder.isMissingPrivateCloudComputeEntitlement(Self.observedError(code: 1047)))
        #expect(!Cassette.Recorder.isMissingPrivateCloudComputeEntitlement(CassetteError.invalidMode("x")))
    }

    @Test("Recording from PCC throws missingEntitlement, with what to do")
    func translated() async {
        await #expect {
            try await Self.recorder(pcc: true).calling { throw Self.observedError() }
        } throws: { error in
            guard case CassetteError.missingEntitlement(_, let entitlement) = error else { return false }
            let message = String(describing: error)
            return entitlement == "com.apple.developer.private-cloud-compute"
                && message.contains("hosted in")
                && message.contains("recording-private-cloud-compute.md")
        }
    }

    @Test("Another model's error passes through unchanged")
    func passesThrough() async {
        await #expect {
            try await Self.recorder(pcc: false).calling { throw Self.observedError() }
        } throws: { error in
            (error as NSError).domain == "FoundationModels.LanguageModelError"
        }
    }
}
