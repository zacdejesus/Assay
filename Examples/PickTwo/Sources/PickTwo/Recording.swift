// Recording Private Cloud Compute. It needs the com.apple.developer.private-cloud-compute
// entitlement, which `swift test` can't have, so RecorderHost (a small signed Mac app) calls
// this. The tapes go to the test target's __Cassettes__ and replay under `swift test`.

import Assay
import Foundation
import FoundationModels

public enum Recording {
    /// The tapes directory of the test target, found from this file's location.
    public static var cassettes: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tests/PickTwoTests/__Cassettes__")
    }

    /// Records one tape per case from Private Cloud Compute, with the recommended setup.
    /// Prints one line per case.
    public static func recordPrivateCloudCompute(into directory: URL = cassettes) async {
        let model = PrivateCloudComputeLanguageModel()
        print("Private Cloud Compute: \(model.availability), quota \(model.quotaUsage.status)")
        for c in Case.all {
            do {
                let cassette = try Cassette(TapeName.cloud(c), mode: .record, recording: model, directory: directory)
                let suggestion = try await Suggester.suggest(c.items, in: c.domain, model: cassette.model)
                print("\(c): \(suggestion.picks.map(\.name).joined(separator: " + "))")
            } catch {
                print("\(c): FAILED \(error)")
            }
        }
    }
}

public enum TapeName {
    public static func onDevice(_ c: Case) -> String { "ondevice-\(c)" }
    public static func cloud(_ c: Case) -> String { "cloud-\(c)" }
}
