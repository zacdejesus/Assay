// The recommended setup, recorded once and replayed with no model.
//
//   swift test                              replay (any Mac with macOS 27, CI included)
//   ASSAY_CASSETTE=record swift test        record the on-device tapes again (Apple Intelligence)
//   Private Cloud Compute tapes:            RecorderHost (README)

import Assay
import Foundation
import FoundationModels
import PickTwo
import Testing

/// What the feature promises, whichever model answered.
func expectGood(_ s: Suggestion, _ c: Case) {
    #expect(s.picks.count == 2, "\(c): \(s.picks.count) picks")
    #expect(Score.coherent(s, in: c.domain) != false, "\(c): \(s.picks.map(\.name)) don't go together")
    #expect(Set(s.picks.map(\.name)).isSubset(of: s.offered))
    for pick in s.picks { #expect(pick.details.count == 3, "\(c): \(pick.name) has \(pick.details.count) details") }
}

let cassettes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Cassettes__")
let cloudTapesExist = FileManager.default.fileExists(atPath: cassettes.appendingPathComponent("cloud-gym-all-fresh.json").path)

@Suite("Tapes", .serialized)
struct TapeTests {

    @Test("On-device model", arguments: Case.all)
    func onDevice(_ c: Case) async throws {
        let cassette = try Cassette(TapeName.onDevice(c))
        let s = try await Suggester.suggest(c.items, in: c.domain, model: cassette.model)
        expectGood(s, c)
    }

    /// Replayed only: recording needs the PCC entitlement, which `swift test` can't have.
    @Test("Private Cloud Compute", .enabled(if: cloudTapesExist), arguments: Case.all)
    func cloud(_ c: Case) async throws {
        let cassette = try Cassette(TapeName.cloud(c), mode: .replay)
        let s = try await Suggester.suggest(c.items, in: c.domain, model: cassette.model)
        expectGood(s, c)
    }

    /// The same requests with the app's random sampling, kept apart so `assay drift` can show
    /// what sampling noise looks like next to the greedy tapes.
    @Test("On-device model, random sampling", arguments: Case.all)
    func randomSampling(_ c: Case) async throws {
        let cassette = try Cassette(TapeName.onDevice(c), directory: cassettes.appendingPathComponent("random-sampling"))
        let s = try await Suggester.suggest(c.items, in: c.domain, model: cassette.model, options: Suggester.appOptions)
        #expect(!s.picks.isEmpty)
    }
}
