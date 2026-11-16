// A tape recorded from the real on-device model and committed. These tests replay it, so
// they run everywhere, including CI machines without Apple Intelligence.
//
// To record it again (after a model update, or after changing a request below), on a Mac
// with Apple Intelligence:
//   scripts/test.sh rerecord
// then update the expected answers below and commit __Cassettes__/on-device.json.

import Assay
import FoundationModels
import Testing

// Serialized: both tests use the same tape, and while recording only one cassette can
// write a file at a time.
@Suite("A tape recorded from the on-device model", .serialized)
struct RecordedTapeTests {

    static let options = GenerationOptions(maximumResponseTokens: 60)

    @Test("Text and a follow-up turn replay exactly as recorded")
    func conversation() async throws {
        let cassette = try Cassette("on-device")
        let session = LanguageModelSession(model: cassette.model, instructions: "Answer in one short sentence.")

        let first = try await session.respond(to: "What is the capital of France?", options: Self.options)
        let second = try await session.respond(to: "And of Italy?", options: Self.options)

        #expect(first.content == "The capital of France is Paris.")
        #expect(second.content == "The capital of Italy is Rome.")
    }

    @Test("Structured output replays into a @Generable type")
    func structured() async throws {
        let cassette = try Cassette("on-device-structured")
        let session = LanguageModelSession(model: cassette.model)

        let trail = try await session.respond(
            to: "Describe a hiking trail in a pine forest.",
            generating: Live.Trail.self,
            options: GenerationOptions(maximumResponseTokens: 120)
        ).content

        #expect(trail.name == "Pine Forest Trail")
        #expect(trail.lengthInKilometers > 0)
        #expect(!trail.highlights.isEmpty)
    }
}
