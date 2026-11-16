// Cassette's unit tests. They record from a FakeModel instead of the real model, so the
// whole cycle (record, write the file, read it, replay) runs offline in milliseconds.

import Foundation
import FoundationModels
import Testing
@testable import Assay

@Suite("Cassette")
struct CassetteTests {

    @Generable
    struct City {
        var name: String
        var population: Int
    }

    /// A directory of its own for each test, removed when the test ends.
    final class Scratch {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("assay-cassette-tests-\(UUID().uuidString)")

        deinit {
            try? FileManager.default.removeItem(at: directory)
        }

        func cassette(
            _ name: String = "tape",
            mode: Cassette.Mode = .auto,
            recording base: FakeModel = FakeModel(),
            environment: [String: String] = [:],
            normalize: (@Sendable (inout Cassette.Request) -> Void)? = nil,
            redact: (@Sendable (String) -> String)? = nil
        ) throws -> Cassette {
            try Cassette(
                name, mode: mode, recording: base, directory: directory,
                normalize: normalize, redact: redact, filePath: #filePath, environment: environment
            )
        }

        func tape(_ name: String = "tape") throws -> Tape {
            try Tape.read(from: directory.appendingPathComponent("\(name).json"))
        }
    }

    // MARK: Record, then replay

    @Test("What was recorded is replayed, without calling the model again")
    func recordThenReplay() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("Paris."))
            #expect(cassette.isRecording)
            let response = try await LanguageModelSession(model: cassette.model).respond(to: "Capital of France?")
            #expect(response.content == "Paris.")
            #expect(cassette.interactionCount == 1)
        }

        let untouched = FakeModel("never used")
        let cassette = try scratch.cassette(recording: untouched)
        #expect(!cassette.isRecording)
        let response = try await LanguageModelSession(model: cassette.model).respond(to: "Capital of France?")
        #expect(response.content == "Paris.")
        #expect(untouched.calls.isEmpty)
    }

    @Test("Replay matches by request, not by order")
    func replayIsKeyed() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("one", "two"))
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "first")
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "second")
        }
        let cassette = try scratch.cassette()
        let second = try await LanguageModelSession(model: cassette.model).respond(to: "second")
        let first = try await LanguageModelSession(model: cassette.model).respond(to: "first")
        #expect(second.content == "two")
        #expect(first.content == "one")
    }

    @Test("A session with several turns replays turn by turn")
    func multipleTurns() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("Apple, pear.", "Carrot, leek."))
            let session = LanguageModelSession(model: cassette.model, instructions: "Be brief.")
            _ = try await session.respond(to: "Two fruits?")
            _ = try await session.respond(to: "Two vegetables?")
        }
        let tape = try scratch.tape()
        #expect(tape.interactions[1].request.instructions == "Be brief.")
        #expect(tape.interactions[1].request.history.map(\.text) == ["Two fruits?", "Apple, pear."])

        let cassette = try scratch.cassette()
        let session = LanguageModelSession(model: cassette.model, instructions: "Be brief.")
        #expect(try await session.respond(to: "Two fruits?").content == "Apple, pear.")
        #expect(try await session.respond(to: "Two vegetables?").content == "Carrot, leek.")
    }

    @Test("Structured output is recorded as JSON and decodes on replay")
    func structuredOutput() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel(.json(#"{"population": 2100000, "name": "Paris"}"#)))
            let city = try await LanguageModelSession(model: cassette.model)
                .respond(to: "Describe Paris.", generating: City.self).content
            #expect(city.name == "Paris")
        }
        let tape = try scratch.tape()
        #expect(tape.interactions[0].response.json == .object(["name": .string("Paris"), "population": .integer(2_100_000)]))
        #expect(tape.interactions[0].request.schema?.contains("population") == true)

        let cassette = try scratch.cassette()
        let city = try await LanguageModelSession(model: cassette.model)
            .respond(to: "Describe Paris.", generating: City.self).content
        #expect(city.name == "Paris")
        #expect(city.population == 2_100_000)
    }

    @Test("A structured turn followed by a text turn replays in one session")
    func structuredThenText() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel(.json(#"{"name": "Lyon", "population": 500000}"#), "On the Rhône."))
            let session = LanguageModelSession(model: cassette.model)
            _ = try await session.respond(to: "Describe Lyon.", generating: City.self)
            _ = try await session.respond(to: "Which river?")
        }
        let cassette = try scratch.cassette()
        let session = LanguageModelSession(model: cassette.model)
        _ = try await session.respond(to: "Describe Lyon.", generating: City.self)
        #expect(try await session.respond(to: "Which river?").content == "On the Rhône.")
    }

    @Test("The same request recorded twice replays in order, and the last answer repeats")
    func repeatedRequest() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("heads", "tails"))
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Flip a coin.")
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Flip a coin.")
        }
        let cassette = try scratch.cassette()
        var answers: [String] = []
        for _ in 0..<3 {
            answers.append(try await LanguageModelSession(model: cassette.model).respond(to: "Flip a coin.").content)
        }
        #expect(answers == ["heads", "tails", "tails"])
    }

    @Test("The recorded token count comes back on replay")
    func tokenCount() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel(.chunks(["a ", "b ", "c"])))
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "abc")
        }
        #expect(try scratch.tape().interactions[0].response.outputTokens == 3)
        let cassette = try scratch.cassette()
        let response = try await LanguageModelSession(model: cassette.model).respond(to: "abc")
        #expect(response.content == "a b c")
        #expect(response.usage.output.totalTokenCount == 3)
    }

    // MARK: Mismatches

    @Test("A request that isn't on the tape fails and shows the closest recording")
    func unknownRequest() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("Paris.", "Rome."))
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Capital of France?")
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Capital of Italy?")
        }
        let untouched = FakeModel("never used")
        let cassette = try scratch.cassette(recording: untouched)
        let error = await #expect(throws: CassetteError.self) {
            try await LanguageModelSession(model: cassette.model).respond(to: "Capital of Spain?")
        }
        guard case .noRecording(_, let requested, let closest, let differences) = try #require(error) else {
            Issue.record("Expected .noRecording, got \(String(describing: error))")
            return
        }
        #expect(requested.prompt == "Capital of Spain?")
        #expect(closest?.prompt.hasPrefix("Capital of ") == true)
        #expect(differences == ["prompt"])
        #expect(error?.description.contains("ASSAY_CASSETTE=record") == true)
        // Replay never falls back to the model.
        #expect(untouched.calls.isEmpty)
    }

    @Test("Instructions and options are part of the match")
    func instructionsAndOptionsMatter() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("Bonjour."))
            _ = try await LanguageModelSession(model: cassette.model, instructions: "Answer in French.")
                .respond(to: "Say hello.", options: GenerationOptions(maximumResponseTokens: 20))
        }
        let cassette = try scratch.cassette()

        let otherInstructions = await #expect(throws: CassetteError.self) {
            try await LanguageModelSession(model: cassette.model, instructions: "Answer in German.")
                .respond(to: "Say hello.", options: GenerationOptions(maximumResponseTokens: 20))
        }
        guard case .noRecording(_, _, _, let first) = try #require(otherInstructions) else { return }
        #expect(first == ["instructions"])

        let otherOptions = await #expect(throws: CassetteError.self) {
            try await LanguageModelSession(model: cassette.model, instructions: "Answer in French.")
                .respond(to: "Say hello.", options: GenerationOptions(maximumResponseTokens: 99))
        }
        guard case .noRecording(_, _, _, let second) = try #require(otherOptions) else { return }
        #expect(second == ["options"])

        let same = try await LanguageModelSession(model: cassette.model, instructions: "Answer in French.")
            .respond(to: "Say hello.", options: GenerationOptions(maximumResponseTokens: 20))
        #expect(same.content == "Bonjour.")
    }

    // MARK: Modes

    @Test("Replay mode fails when the tape is missing, and says how to record it")
    func missingTape() throws {
        let scratch = Scratch()
        let error = #expect(throws: CassetteError.self) {
            try scratch.cassette("absent", mode: .replay)
        }
        guard case .missingTape(let tape, _) = try #require(error) else {
            Issue.record("Expected .missingTape, got \(String(describing: error))")
            return
        }
        #expect(tape == "absent")
        #expect(error?.description.contains("ASSAY_CASSETTE=record") == true)
    }

    @Test("In CI nothing is recorded: auto fails on a missing tape, record is refused")
    func neverRecordsInCI() throws {
        let scratch = Scratch()
        let model = FakeModel("unused")
        let auto = #expect(throws: CassetteError.self) {
            try scratch.cassette(recording: model, environment: ["CI": "true"])
        }
        guard case .missingTape = try #require(auto) else {
            Issue.record("Expected .missingTape, got \(String(describing: auto))")
            return
        }
        let record = #expect(throws: CassetteError.self) {
            try scratch.cassette(mode: .record, recording: model, environment: ["CI": "true"])
        }
        guard case .recordingInCI = try #require(record) else {
            Issue.record("Expected .recordingInCI, got \(String(describing: record))")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.directory.path))
    }

    @Test("ASSAY_CASSETTE=record replaces an existing tape")
    func environmentOverride() async throws {
        let scratch = Scratch()
        do {
            let cassette = try scratch.cassette(recording: FakeModel("old", "stale"))
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "q")
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "dropped")
        }
        do {
            let cassette = try scratch.cassette(recording: FakeModel("new"), environment: ["ASSAY_CASSETTE": "record"])
            #expect(cassette.isRecording)
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "q")
        }
        let tape = try scratch.tape()
        #expect(tape.interactions.map(\.response.text) == ["new"])

        #expect(throws: CassetteError.self) {
            try scratch.cassette(environment: ["ASSAY_CASSETTE": "rewind"])
        }

        // A mode chosen in code wins over the environment.
        let replaying = try scratch.cassette(mode: .replay, environment: ["ASSAY_CASSETTE": "record"])
        #expect(!replaying.isRecording)
    }

    @Test("Two cassettes can't record to the same tape at once")
    func oneRecorderPerTape() throws {
        let scratch = Scratch()
        let first = try scratch.cassette(mode: .record)
        let error = #expect(throws: CassetteError.self) {
            try scratch.cassette(mode: .record)
        }
        guard case .tapeInUse = try #require(error) else {
            Issue.record("Expected .tapeInUse, got \(String(describing: error))")
            return
        }
        _ = first
    }

    // MARK: Recording

    @Test("Recording uses greedy sampling unless the test chose a mode")
    func greedyByDefault() async throws {
        let scratch = Scratch()
        let model = FakeModel("a", "b")
        let cassette = try scratch.cassette(recording: model)
        _ = try await LanguageModelSession(model: cassette.model).respond(to: "default")
        _ = try await LanguageModelSession(model: cassette.model)
            .respond(to: "chosen", options: GenerationOptions(samplingMode: .random(top: 10, seed: 7)))

        #expect(model.calls[0].options.samplingMode == .greedy)
        #expect(model.calls[1].options.samplingMode == .random(top: 10, seed: 7))

        let tape = try scratch.tape()
        // The request keeps what the test asked for; the provenance says what was used.
        #expect(tape.interactions[0].request.options.sampling == nil)
        #expect(tape.interactions[0].provenance.sampling.mode == "greedy")
        #expect(tape.interactions[1].provenance.sampling.top == 10)
        #expect(tape.interactions[1].provenance.sampling.seed == 7)
    }

    @Test("The model receives the same instructions and earlier turns as the session")
    func recorderForwardsTheConversation() async throws {
        let scratch = Scratch()
        let model = FakeModel("one", "two")
        let cassette = try scratch.cassette(recording: model)
        let session = LanguageModelSession(model: cassette.model, instructions: "Be brief.")
        _ = try await session.respond(to: "first")
        _ = try await session.respond(to: "second")
        // instructions, prompt, response, prompt
        #expect(model.calls[1].transcript.count == 4)
        #expect(model.calls[1].prompt == "second")
    }

    @Test("A prompt built from several parts reaches the model with the same parts")
    func promptParts() async throws {
        let scratch = Scratch()
        let model = FakeModel("ok")
        let cassette = try scratch.cassette(recording: model)
        _ = try await LanguageModelSession(model: cassette.model).respond {
            "# Title"
            "Line two"
        }
        guard case .prompt(let prompt) = model.calls[0].transcript.last else {
            Issue.record("The model didn't receive a prompt")
            return
        }
        let parts = prompt.segments.map { segment -> String in
            if case .text(let text) = segment { text.content } else { "" }
        }
        #expect(parts == ["# Title", "Line two"])
        #expect(try scratch.tape().interactions[0].request.prompt == "# Title\nLine two")
    }

    @Test("An error from the model while recording reaches the test and isn't recorded")
    func recordingFailure() async throws {
        struct Offline: Error {}
        let scratch = Scratch()
        let cassette = try scratch.cassette(recording: FakeModel(.failure(Offline())))
        await #expect(throws: Offline.self) {
            try await LanguageModelSession(model: cassette.model).respond(to: "hi")
        }
        #expect(cassette.interactionCount == 0)
    }

    // MARK: Hooks

    @Test("normalize makes requests that differ only in noise match")
    func normalizeHook() async throws {
        let scratch = Scratch()
        let stripDate: @Sendable (inout Cassette.Request) -> Void = { request in
            request.prompt = request.prompt.replacing(/\d{4}-\d{2}-\d{2}/, with: "<date>")
        }
        do {
            let cassette = try scratch.cassette(recording: FakeModel("Monday."), normalize: stripDate)
            _ = try await LanguageModelSession(model: cassette.model).respond(to: "Today is 2026-11-16. What day is it?")
        }
        #expect(try scratch.tape().interactions[0].request.prompt == "Today is <date>. What day is it?")
        let cassette = try scratch.cassette(normalize: stripDate)
        let response = try await LanguageModelSession(model: cassette.model).respond(to: "Today is 2027-01-02. What day is it?")
        #expect(response.content == "Monday.")
    }

    @Test("redact keeps a secret out of the file")
    func redactHook() async throws {
        let scratch = Scratch()
        let cassette = try scratch.cassette(
            recording: FakeModel("Your key is sk-12345."),
            redact: { $0.replacingOccurrences(of: "sk-12345", with: "<key>") }
        )
        let response = try await LanguageModelSession(model: cassette.model).respond(to: "My key?")
        #expect(response.content == "Your key is <key>.")
        let file = try String(contentsOf: cassette.url, encoding: .utf8)
        #expect(!file.contains("sk-12345"))
    }

    // MARK: The file

    @Test("The tape is versioned, and another version is rejected")
    func tapeVersion() async throws {
        let scratch = Scratch()
        let cassette = try scratch.cassette(recording: FakeModel("hi"))
        _ = try await LanguageModelSession(model: cassette.model).respond(to: "hello")
        let tape = try scratch.tape()
        #expect(tape.version == 1)
        #expect(tape.interactions[0].key.count == 64)

        let text = try String(contentsOf: cassette.url, encoding: .utf8)
        try text.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
            .write(to: scratch.directory.appendingPathComponent("future.json"), atomically: true, encoding: .utf8)
        let error = #expect(throws: CassetteError.self) {
            try scratch.cassette("future", mode: .replay)
        }
        guard case .unsupportedTapeVersion(let version, _) = try #require(error) else {
            Issue.record("Expected .unsupportedTapeVersion, got \(String(describing: error))")
            return
        }
        #expect(version == 2)
    }

    @Test("The same request always gets the same key")
    func keysAreStable() throws {
        let request = try JSONDecoder().decode(
            Cassette.Request.self,
            from: Data(#"{"history": [], "prompt": "hi", "options": {"maximumResponseTokens": 5}}"#.utf8)
        )
        // Fixed values: if either changes, every committed tape stops matching.
        #expect(try Canonical.key(for: request) == "a37eb12d47f85c08368c7b6554224499f45ac0197b966cd4e1bcadc9792052f6")
        #expect(String(decoding: try Canonical.encode(request), as: UTF8.self)
            == #"{"history":[],"options":{"maximumResponseTokens":5},"prompt":"hi"}"#)
    }
}
