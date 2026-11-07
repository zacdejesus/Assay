// Experiment A (M0 spike): the smallest custom LanguageModel, used to learn how a
// LanguageModelSession talks to a model.
//
// The tests below are characterization tests: they pin down framework behavior that
// Assay's design depends on (findings in docs/notes/foundationmodels.md). If a new OS
// changes any of it, the failing test names the assumption that broke.

import FoundationModels
import Testing

@Suite("Experiment A: a fake LanguageModel")
struct ExperimentATests {

    /// What the fake executor does on each request. Chosen on the model and carried
    /// to the executor through its Configuration.
    enum Behavior: Hashable, Sendable {
        /// Streams "hello".
        case hello
        /// Returns without sending any event.
        case silent
        /// Answers with the number of entries in the request's transcript, so a test
        /// can see what the executor received without any shared state.
        case echoTranscriptCount
    }

    /// Executor of the fake model: the part that actually produces the answer.
    struct HelloExecutor: LanguageModelExecutor {
        /// The model and its executor point at each other (`Self == Executor.Model`).
        typealias Model = HelloModel

        /// Everything the executor needs from the model. Hashable & Sendable is what
        /// the protocol requires.
        struct Configuration: Hashable, Sendable {
            var behavior: Behavior
        }

        private let behavior: Behavior

        /// The protocol's init is `throws`; a non-throwing one satisfies it.
        init(configuration: Configuration) {
            behavior = configuration.behavior
        }

        func prewarm(model: HelloModel, transcript: Transcript) {}

        /// Doesn't return the answer: it sends events into the channel the session
        /// reads, and returning ends the response.
        nonisolated(nonsending) func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: HelloModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            // `tokenCount` is made up: the fake reports no real usage.
            switch behavior {
            case .hello:
                await channel.send(.response(action: .appendText("hello", tokenCount: 1)))
            case .silent:
                break
            case .echoTranscriptCount:
                let count = String(request.transcript.count)
                await channel.send(.response(action: .appendText(count, tokenCount: 1)))
            }
        }
    }

    /// The fake model: a lightweight description the session uses to build the executor.
    struct HelloModel: LanguageModel {
        typealias Executor = HelloExecutor

        var behavior: Behavior = .hello

        /// Plain text only: no guided generation, tools, reasoning or vision.
        var capabilities: LanguageModelCapabilities { .init([]) }

        var executorConfiguration: HelloExecutor.Configuration { .init(behavior: behavior) }
    }

    /// A minimal structured-output type for the capabilities test.
    @Generable
    struct Greeting {
        var text: String
    }

    @Test("A custom model backs a real session in a plain unit test")
    func fakeModelAnswersHello() async throws {
        let session = LanguageModelSession(model: HelloModel())
        let response = try await session.respond(to: "hi")
        #expect(response.content == "hello")
    }

    @Test("An executor that sends nothing makes the session throw ParsingError")
    func silentExecutorThrowsParsingError() async {
        let session = LanguageModelSession(model: HelloModel(behavior: .silent))
        await #expect(throws: GeneratedContent.ParsingError.self) {
            try await session.respond(to: "hi")
        }
    }

    @Test("The request transcript accumulates earlier turns")
    func requestTranscriptAccumulates() async throws {
        let session = LanguageModelSession(model: HelloModel(behavior: .echoTranscriptCount))
        let first = try await session.respond(to: "first")
        let second = try await session.respond(to: "second")
        #expect(first.content == "1")   // prompt
        #expect(second.content == "3")  // prompt, response, prompt
    }

    @Test("Capabilities are enforced before the executor is called")
    func missingCapabilityIsRejected() async throws {
        let session = LanguageModelSession(model: HelloModel())
        let error = await #expect(throws: LanguageModelError.self) {
            try await session.respond(to: "hi", generating: Greeting.self)
        }
        guard case .unsupportedCapability = try #require(error) else {
            Issue.record("Expected .unsupportedCapability, got \(String(describing: error))")
            return
        }
    }
}
