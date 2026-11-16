import Assay
import Foundation
import FoundationModels
import Testing

@Suite("FakeModel")
struct FakeModelTests {

    @Generable
    struct Trail {
        var name: String
        var lengthInKilometers: Int
    }

    struct Offline: Error, Equatable {}

    // MARK: Scripted answers

    @Test("A string literal is a text answer")
    func fixedAnswer() async throws {
        let session = LanguageModelSession(model: FakeModel("hello"))
        let response = try await session.respond(to: "hi")
        #expect(response.content == "hello")
    }

    @Test("Responses are given in order, one per call")
    func queueOrder() async throws {
        let session = LanguageModelSession(model: FakeModel(.text("first"), .text("second")))
        #expect(try await session.respond(to: "1").content == "first")
        #expect(try await session.respond(to: "2").content == "second")
    }

    @Test("An array of responses works like the variadic form")
    func arrayInit() async throws {
        let script: [FakeModel.Response] = ["a", "b"]
        let session = LanguageModelSession(model: FakeModel(script))
        #expect(try await session.respond(to: "1").content == "a")
        #expect(try await session.respond(to: "2").content == "b")
    }

    @Test("Chunks arrive joined")
    func chunksAreJoined() async throws {
        let session = LanguageModelSession(model: FakeModel(.chunks(["Boil ", "water."])))
        #expect(try await session.respond(to: "hi").content == "Boil water.")
    }

    @Test("A closure decides per request and never runs out")
    func closureAnswers() async throws {
        let model = FakeModel { request in .text("entries: \(request.transcript.count)") }
        let session = LanguageModelSession(model: model)
        #expect(try await session.respond(to: "1").content == "entries: 1")
        #expect(try await session.respond(to: "2").content == "entries: 3")
        #expect(try await session.respond(to: "3").content == "entries: 5")
    }

    // MARK: Running out

    @Test("A call after the last response throws noResponseLeft")
    func runsOut() async throws {
        let session = LanguageModelSession(model: FakeModel("only one"))
        _ = try await session.respond(to: "1")
        let error = await #expect(throws: FakeModelError.self) {
            try await session.respond(to: "2")
        }
        #expect(error == .noResponseLeft(call: 2, scripted: 1))
    }

    @Test("The failure message says what happened and what to do")
    func failureMessage() {
        let message = FakeModelError.noResponseLeft(call: 3, scripted: 2).description
        #expect(message.contains("call 3"))
        #expect(message.contains("2 responses were scripted"))
        #expect(FakeModelError.noResponseLeft(call: 2, scripted: 1).description.contains("1 response was scripted"))
    }

    @Test("An empty script fails on the first call")
    func emptyScript() async {
        let session = LanguageModelSession(model: FakeModel())
        let error = await #expect(throws: FakeModelError.self) {
            try await session.respond(to: "hi")
        }
        #expect(error == .noResponseLeft(call: 1, scripted: 0))
    }

    // MARK: Errors and latency

    @Test("A scripted failure reaches the caller unchanged")
    func scriptedFailure() async {
        let session = LanguageModelSession(model: FakeModel(.failure(Offline())))
        await #expect(throws: Offline.self) {
            try await session.respond(to: "hi")
        }
    }

    @Test("After a failure the next response is still given")
    func failureThenAnswer() async throws {
        let session = LanguageModelSession(model: FakeModel(.failure(Offline()), "recovered"))
        await #expect(throws: Offline.self) {
            try await session.respond(to: "1")
        }
        #expect(try await session.respond(to: "2").content == "recovered")
    }

    @Test("A delayed response waits before answering")
    func delayedResponse() async throws {
        let session = LanguageModelSession(model: FakeModel(.text("late").delayed(by: .milliseconds(80))))
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await session.respond(to: "hi")
        #expect(response.content == "late")
        #expect(start.duration(to: clock.now) >= .milliseconds(80))
    }

    // MARK: Structured output and capabilities

    @Test("A JSON response decodes into a @Generable type")
    func structuredOutput() async throws {
        let model = FakeModel(.json(#"{"name": "Pine Trail", "lengthInKilometers": 5}"#))
        let response = try await LanguageModelSession(model: model).respond(to: "hi", generating: Trail.self)
        #expect(response.content.name == "Pine Trail")
        #expect(response.content.lengthInKilometers == 5)
    }

    @Test("A text-only script doesn't claim guided generation")
    func textOnlyRejectsStructuredRequests() async throws {
        let model = FakeModel("just text")
        let error = await #expect(throws: LanguageModelError.self) {
            try await LanguageModelSession(model: model).respond(to: "hi", generating: Trail.self)
        }
        guard case .unsupportedCapability = try #require(error) else {
            Issue.record("Expected .unsupportedCapability, got \(String(describing: error))")
            return
        }
        // The session rejected the request before it reached the model.
        #expect(model.calls.isEmpty)
    }

    @Test("Capabilities can be declared explicitly")
    func explicitCapabilities() async throws {
        let model = FakeModel(capabilities: .init([.guidedGeneration])) { _ in
            .json(#"{"name": "Ridge", "lengthInKilometers": 12}"#)
        }
        let response = try await LanguageModelSession(model: model).respond(to: "hi", generating: Trail.self)
        #expect(response.content.name == "Ridge")
    }

    // MARK: Call log

    @Test("Calls record the prompt, the options and the kind of request")
    func callLog() async throws {
        let model = FakeModel(.text("a"), .json(#"{"name": "x", "lengthInKilometers": 1}"#))
        let session = LanguageModelSession(model: model)
        _ = try await session.respond(to: "first prompt", options: GenerationOptions(maximumResponseTokens: 42))
        _ = try await session.respond(to: "second prompt", generating: Trail.self)

        #expect(model.calls.count == 2)
        #expect(model.calls[0].prompt == "first prompt")
        #expect(model.calls[0].options.maximumResponseTokens == 42)
        #expect(model.calls[0].expectsStructuredOutput == false)
        #expect(model.calls[1].prompt == "second prompt")
        #expect(model.calls[1].expectsStructuredOutput == true)
        // The second request carries the first turn too.
        #expect(model.calls[1].transcript.count == 3)
    }

    @Test("A failed call is recorded too")
    func failedCallIsRecorded() async {
        let model = FakeModel()
        _ = try? await LanguageModelSession(model: model).respond(to: "hi")
        #expect(model.calls.count == 1)
    }

    @Test("Sessions built from the same model share one script and one call log")
    func sharedAcrossSessions() async throws {
        let model = FakeModel("first", "second")
        let one = try await LanguageModelSession(model: model).respond(to: "a")
        let two = try await LanguageModelSession(model: model).respond(to: "b")
        #expect(one.content == "first")
        #expect(two.content == "second")
        #expect(model.calls.map(\.prompt) == ["a", "b"])
    }

    @Test("Concurrent calls each get exactly one response")
    func concurrentCalls() async throws {
        let count = 50
        let model = FakeModel((0..<count).map { .text("answer \($0)") })
        let answers = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<count {
                group.addTask {
                    try await LanguageModelSession(model: model).respond(to: "prompt \(index)").content
                }
            }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(answers == Set((0..<count).map { "answer \($0)" }))
        #expect(model.calls.count == count)
    }
}
