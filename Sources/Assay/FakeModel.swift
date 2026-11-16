import Foundation
import FoundationModels
import Synchronization

/// A scripted language model for unit tests.
///
/// `FakeModel` conforms to Apple's `LanguageModel`, so it backs a real
/// `LanguageModelSession`. Tests run in milliseconds and don't need Apple Intelligence.
///
/// ```swift
/// let model = FakeModel("Boil water.", "Add pasta.")
/// let session = LanguageModelSession(model: model)
///
/// let first = try await session.respond(to: "Step one?")   // "Boil water."
/// let second = try await session.respond(to: "Step two?")  // "Add pasta."
///
/// #expect(model.calls.count == 2)
/// #expect(model.calls[0].prompt == "Step one?")
/// ```
///
/// Responses are used once each, in order. A call made after the last one throws
/// ``FakeModelError/noResponseLeft(call:scripted:)``, so a test notices when the model is
/// called more often than it expected. To answer any number of calls, use
/// ``init(capabilities:respond:)``.
///
/// Copies of a `FakeModel` share one script and one call log. That is what lets several
/// sessions built from the same model consume the same queue.
public struct FakeModel: LanguageModel {

    /// One scripted answer.
    ///
    /// A string literal is a text response, so `FakeModel("hello")` works.
    public struct Response: Sendable, ExpressibleByStringLiteral {
        enum Content: Sendable {
            case chunks([String])
            case failure(any Swift.Error)
        }

        var content: Content
        var delay: Duration?
        var needsGuidedGeneration = false

        /// A plain text answer.
        public static func text(_ text: String) -> Response {
            Response(content: .chunks([text]))
        }

        /// A plain text answer sent in several pieces, as a streaming model would.
        ///
        /// The session may merge pieces before the caller sees them, so don't assert an
        /// exact sequence of stream snapshots. The final content is the pieces joined.
        public static func chunks(_ chunks: [String]) -> Response {
            Response(content: .chunks(chunks))
        }

        /// A structured answer, as JSON text.
        ///
        /// Use it for `respond(to:generating:)`. The JSON has to match the `@Generable`
        /// type the test asks for; if it doesn't, the session throws its own decoding error.
        public static func json(_ json: String) -> Response {
            Response(content: .chunks([json]), needsGuidedGeneration: true)
        }

        /// Makes the call throw `error`. The caller receives it unchanged.
        ///
        /// ```swift
        /// FakeModel(.failure(MyNetworkError.offline))
        /// ```
        public static func failure(_ error: any Swift.Error) -> Response {
            Response(content: .failure(error))
        }

        /// Waits before answering, to test timeouts and loading states.
        public func delayed(by delay: Duration) -> Response {
            var copy = self
            copy.delay = delay
            return copy
        }

        public init(stringLiteral value: String) {
            self = .text(value)
        }

        init(content: Content, delay: Duration? = nil, needsGuidedGeneration: Bool = false) {
            self.content = content
            self.delay = delay
            self.needsGuidedGeneration = needsGuidedGeneration
        }
    }

    /// One request the model received.
    public struct Call: Sendable {
        /// The text of the prompt that triggered this call, if it had any.
        public var prompt: String?
        /// Everything the session sent: instructions, earlier turns and this prompt.
        public var transcript: Transcript
        /// The options the caller passed.
        public var options: GenerationOptions
        /// Whether the caller asked for structured output.
        public var expectsStructuredOutput: Bool
    }

    let state: State
    private let declaredCapabilities: LanguageModelCapabilities

    /// A model that gives `responses` in order, one per call.
    ///
    /// - Parameters:
    ///   - responses: The script. Each response is used once.
    ///   - capabilities: What the model claims to support. By default it is worked out
    ///     from the script: guided generation only if a ``Response/json(_:)`` is scripted.
    ///     The session rejects requests the model doesn't claim to support.
    public init(_ responses: Response..., capabilities: LanguageModelCapabilities? = nil) {
        self.init(responses, capabilities: capabilities)
    }

    /// A model that gives `responses` in order, one per call.
    public init(_ responses: [Response], capabilities: LanguageModelCapabilities? = nil) {
        let structured = responses.contains { $0.needsGuidedGeneration }
        self.state = State(script: responses, respond: nil)
        self.declaredCapabilities = capabilities ?? .init(structured ? [.guidedGeneration] : [])
    }

    /// A model that decides its answer for each request. It never runs out.
    ///
    /// ```swift
    /// let model = FakeModel { request in
    ///     .text("I saw \(request.transcript.count) entries")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - capabilities: What the model claims to support. Text only by default; pass
    ///     `.init([.guidedGeneration])` if the closure returns ``Response/json(_:)``.
    ///   - respond: Called once per request, possibly from several tasks at once.
    public init(
        capabilities: LanguageModelCapabilities = .init([]),
        respond: @escaping @Sendable (LanguageModelExecutorGenerationRequest) -> Response
    ) {
        self.state = State(script: [], respond: respond)
        self.declaredCapabilities = capabilities
    }

    /// Every request received so far, in order, across all sessions using this model.
    public var calls: [Call] {
        state.calls
    }

    public var capabilities: LanguageModelCapabilities {
        declaredCapabilities
    }

    public var executorConfiguration: Executor.Configuration {
        Executor.Configuration(state: state)
    }

    /// Produces the scripted answers. Created by the session; tests don't use it directly.
    public struct Executor: LanguageModelExecutor {
        public typealias Model = FakeModel

        public struct Configuration: Hashable, Sendable {
            let state: State
        }

        private let state: State

        public init(configuration: Configuration) {
            state = configuration.state
        }

        public func prewarm(model: FakeModel, transcript: Transcript) {}

        nonisolated(nonsending) public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: FakeModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            let response = try state.nextResponse(for: request)
            if let delay = response.delay {
                try await Task.sleep(for: delay)
            }
            switch response.content {
            case .failure(let error):
                throw error
            case .chunks(let chunks):
                for chunk in chunks {
                    // The token count is made up: a fake has no tokenizer.
                    await channel.send(.response(action: .appendText(chunk, tokenCount: 1)))
                }
            }
        }
    }

    /// The script position and the call log. A reference type because the session creates
    /// one executor per session and only hands it the model's configuration: state that
    /// must outlive a session has to be reachable from there.
    final class State: Sendable, Hashable {
        private struct Storage {
            var next = 0
            var calls: [Call] = []
        }

        private let script: [Response]
        private let respond: (@Sendable (LanguageModelExecutorGenerationRequest) -> Response)?
        private let storage = Mutex(Storage())

        init(script: [Response], respond: (@Sendable (LanguageModelExecutorGenerationRequest) -> Response)?) {
            self.script = script
            self.respond = respond
        }

        var calls: [Call] {
            storage.withLock { $0.calls }
        }

        func nextResponse(for request: LanguageModelExecutorGenerationRequest) throws -> Response {
            let call = Call(
                prompt: Self.lastPromptText(in: request.transcript),
                transcript: request.transcript,
                options: request.generationOptions,
                expectsStructuredOutput: request.schema != nil
            )
            let index = storage.withLock { storage -> Int in
                storage.calls.append(call)
                defer { storage.next += 1 }
                return storage.next
            }
            if let respond {
                return respond(request)
            }
            guard index < script.count else {
                throw FakeModelError.noResponseLeft(call: index + 1, scripted: script.count)
            }
            return script[index]
        }

        private static func lastPromptText(in transcript: Transcript) -> String? {
            for entry in transcript.reversed() {
                guard case .prompt(let prompt) = entry else { continue }
                let text = prompt.segments.compactMap { segment -> String? in
                    if case .text(let text) = segment { return text.content }
                    return nil
                }
                return text.isEmpty ? nil : text.joined()
            }
            return nil
        }

        // Identity, not contents: two models are the same script only if they share it.
        static func == (lhs: State, rhs: State) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}

/// What ``FakeModel`` throws on its own account.
public enum FakeModelError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// The model was called more often than responses were scripted.
    /// - Parameters:
    ///   - call: Which call failed, counting from 1.
    ///   - scripted: How many responses the script had.
    case noResponseLeft(call: Int, scripted: Int)

    public var description: String {
        switch self {
        case .noResponseLeft(let call, let scripted):
            let responses = scripted == 1 ? "1 response was" : "\(scripted) responses were"
            return "FakeModel has no response left: this is call \(call), but only \(responses) scripted. "
                + "Script another response, or check why the model is called more often than the test expects."
        }
    }

    public var errorDescription: String? {
        description
    }
}
