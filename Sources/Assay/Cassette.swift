// Cassette: record what a model answered, replay it anywhere.
// Design and the experiment behind it: docs/decisions/0005-cassette.md

import Foundation
import FoundationModels
import Synchronization

/// A recording of a model's answers, kept in a file next to the test.
///
/// ```swift
/// @Test func capital() async throws {
///     let cassette = try Cassette("capital")
///     let session = LanguageModelSession(model: cassette.model)
///
///     let response = try await session.respond(to: "What is the capital of France?")
///     #expect(response.content.contains("Paris"))
/// }
/// ```
///
/// The first run calls the real model and writes `__Cassettes__/capital.json` next to the
/// test file. Every run after that reads the file: no model, no Apple Intelligence, the same
/// answer every time. Commit the file, and the test runs in CI.
///
/// **Matching.** A request is answered only by a recording of the same request: same
/// instructions, earlier turns, prompt, schema and options. If the test asks for something
/// that isn't on the tape, the call throws ``CassetteError/noRecording(tape:requested:closest:differences:)``.
/// It never falls back to the real model while replaying.
///
/// **Recording again.** Run the test with `ASSAY_CASSETTE=record`. The tape is rewritten
/// from scratch. A tape is a snapshot of one model; its file says which one.
///
/// **In CI** (when the `CI` environment variable is set) nothing is ever recorded: a
/// missing tape is a failure.
public final class Cassette: Sendable {

    public enum Mode: String, Sendable {
        /// Only read the tape. A missing tape or a request that isn't on it is a failure.
        case replay
        /// Call the model and write a new tape, replacing any existing one.
        case record
        /// Replay if the tape exists, record if it doesn't. The default.
        case auto
    }

    /// The model to build sessions with.
    public let model: Model

    /// Where the tape is.
    public var url: URL { state.url }

    /// Whether this cassette calls the real model and writes the tape.
    public var isRecording: Bool { state.recorder != nil }

    /// How many interactions the tape holds right now.
    public var interactionCount: Int { state.interactionCount }

    private let state: State

    /// Opens a cassette.
    ///
    /// - Parameters:
    ///   - name: The tape's file name, without extension.
    ///   - mode: See ``Mode``. In `.auto`, the `ASSAY_CASSETTE` environment variable
    ///     (`record` or `replay`) decides, so a tape can be recorded again without editing
    ///     the test. A mode chosen in code is not overridden.
    ///   - base: The model to record from.
    ///   - directory: Where the tape lives. By default, `__Cassettes__` next to the file
    ///     that calls this initializer.
    ///   - normalize: Changes a request before it is matched and stored. Use it to blank
    ///     out what differs between runs, such as a date inside a prompt.
    ///   - redact: Changes a response's text before it is stored. What it removes never
    ///     reaches the file, and replay returns the redacted text.
    ///   - filePath: Leave the default.
    public convenience init<Base: LanguageModel>(
        _ name: String,
        mode: Mode = .auto,
        recording base: Base = SystemLanguageModel.default,
        directory: URL? = nil,
        normalize: (@Sendable (inout Request) -> Void)? = nil,
        redact: (@Sendable (String) -> String)? = nil,
        filePath: StaticString = #filePath
    ) throws {
        try self.init(
            name,
            mode: mode,
            recording: base,
            directory: directory,
            normalize: normalize,
            redact: redact,
            filePath: filePath,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// The same, with the environment passed in so tests can set it.
    init<Base: LanguageModel>(
        _ name: String,
        mode: Mode,
        recording base: Base,
        directory: URL?,
        normalize: (@Sendable (inout Request) -> Void)?,
        redact: (@Sendable (String) -> String)?,
        filePath: StaticString,
        environment: [String: String]
    ) throws {
        let directory = directory
            ?? URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent().appendingPathComponent("__Cassettes__")
        let url = directory.appendingPathComponent("\(name).json")
        let exists = FileManager.default.fileExists(atPath: url.path)
        let inCI = !(environment["CI"] ?? "").isEmpty

        // The environment decides for cassettes in auto mode. A test that asks for
        // `.replay` or `.record` in code gets exactly that.
        var mode = mode
        if mode == .auto, let override = environment["ASSAY_CASSETTE"], !override.isEmpty {
            guard let parsed = Mode(rawValue: override) else {
                throw CassetteError.invalidMode(override)
            }
            mode = parsed
        }

        let records: Bool
        switch mode {
        case .record:
            guard !inCI else { throw CassetteError.recordingInCI(tape: name) }
            records = true
        case .replay:
            records = false
        case .auto:
            records = !exists && !inCI
        }

        if records {
            if let system = base as? SystemLanguageModel, case .unavailable(let reason) = system.availability {
                throw CassetteError.modelUnavailable(tape: name, reason: String(describing: reason))
            }
            let recorder = Recorder(
                capabilities: base.capabilities,
                makeSession: { transcript in LanguageModelSession(model: base, transcript: transcript) }
            )
            state = try State(name: name, url: url, tape: Tape(machine: Tape.currentMachine), recorder: recorder, normalize: normalize, redact: redact)
        } else {
            guard exists else { throw CassetteError.missingTape(tape: name, path: url.path) }
            state = try State(name: name, url: url, tape: Tape.read(from: url), recorder: nil, normalize: normalize, redact: redact)
        }
        model = Model(state: state)
    }

    // MARK: - The model

    /// A `LanguageModel` that answers from the tape, or records onto it.
    public struct Model: LanguageModel {
        public typealias Executor = Cassette.Executor

        let state: State

        /// While recording, what the recorded model supports. While replaying, guided
        /// generation is always claimed: what the tape holds decides what can be answered.
        public var capabilities: LanguageModelCapabilities {
            state.recorder?.capabilities ?? .init([.guidedGeneration])
        }

        public var executorConfiguration: Executor.Configuration {
            Executor.Configuration(state: state)
        }
    }

    /// Created by the session; tests don't use it directly.
    public struct Executor: LanguageModelExecutor {
        public typealias Model = Cassette.Model

        public struct Configuration: Hashable, Sendable {
            let state: State
        }

        private let state: State

        public init(configuration: Configuration) {
            state = configuration.state
        }

        public func prewarm(model: Cassette.Model, transcript: Transcript) {}

        nonisolated(nonsending) public func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: Cassette.Model,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            var key = try Request(request)
            state.normalize?(&key)

            let response: Tape.Response
            if let recorder = state.recorder {
                response = try await state.record(key, original: request, with: recorder)
            } else {
                response = try state.replay(key)
            }
            // Recording and replay answer through this same line, in one piece, so a test
            // behaves the same way in both.
            await channel.send(.response(action: .appendText(try response.emitted, tokenCount: response.outputTokens)))
        }
    }

    struct Recorder: Sendable {
        var capabilities: LanguageModelCapabilities
        var makeSession: @Sendable (Transcript) -> LanguageModelSession
    }

    // MARK: - State

    /// The tape in memory. A reference type for the same reason as `FakeModel.State`: the
    /// session creates one executor per session and hands it only the configuration.
    final class State: Sendable, Hashable {
        private struct Storage {
            var tape: Tape
            /// How many times each key has been replayed, to give repeated requests their
            /// answers in the order they were recorded.
            var replays: [String: Int] = [:]
        }

        let name: String
        let url: URL
        let recorder: Recorder?
        let normalize: (@Sendable (inout Request) -> Void)?
        let redact: (@Sendable (String) -> String)?
        private let storage: Mutex<Storage>

        /// Tapes being recorded in this process. Two cassettes writing one file would
        /// each overwrite the other's interactions.
        private static let recording = Mutex<Set<String>>([])

        init(
            name: String,
            url: URL,
            tape: Tape,
            recorder: Recorder?,
            normalize: (@Sendable (inout Request) -> Void)?,
            redact: (@Sendable (String) -> String)?
        ) throws {
            if recorder != nil {
                let path = url.standardizedFileURL.path
                let inserted = Self.recording.withLock { $0.insert(path).inserted }
                guard inserted else { throw CassetteError.tapeInUse(path: url.path) }
            }
            self.name = name
            self.url = url
            self.recorder = recorder
            self.normalize = normalize
            self.redact = redact
            self.storage = Mutex(Storage(tape: tape))
        }

        deinit {
            if recorder != nil {
                let path = url.standardizedFileURL.path
                Self.recording.withLock { _ = $0.remove(path) }
            }
        }

        var interactionCount: Int {
            storage.withLock { $0.tape.interactions.count }
        }

        func replay(_ request: Request) throws -> Tape.Response {
            let key = try Canonical.key(for: request)
            return try storage.withLock { storage in
                let matches = storage.tape.interactions.filter { $0.key == key }
                guard !matches.isEmpty else {
                    let recorded = storage.tape.interactions.map(\.request)
                    let closest = Self.closest(to: request, in: recorded)
                    throw CassetteError.noRecording(
                        tape: name,
                        requested: request,
                        closest: closest,
                        differences: closest.map(request.differences(from:)) ?? []
                    )
                }
                // The same request recorded several times: answers in order, the last repeats.
                let index = storage.replays[key, default: 0]
                storage.replays[key] = index + 1
                return matches[min(index, matches.count - 1)].response
            }
        }

        nonisolated(nonsending) func record(
            _ request: Request,
            original: LanguageModelExecutorGenerationRequest,
            with recorder: Recorder
        ) async throws -> Tape.Response {
            // Recording happens at the session level: a session's response and transcript
            // are public API, the executor's events are not. So the request is run again
            // in a session of its own, built from everything but the last prompt.
            let session = recorder.makeSession(Transcript(entries: original.transcript.dropLast()))

            // Greedy unless the test chose a sampling mode: a tape should hold what the
            // model says, not one draw of the dice.
            // The prompt is rebuilt part by part, so the model receives the same segments
            // the test sent, not one joined string.
            guard case .prompt(let last) = original.transcript.last else {
                throw CassetteError.unsupported("a request that doesn't end with a prompt")
            }
            let prompt = Prompt(try Request.parts(of: last.segments))

            var options = original.generationOptions
            if options.samplingMode == nil {
                options.samplingMode = .greedy
            }

            var response: Tape.Response
            let entries: [Transcript.Entry]
            if let schema = original.schema {
                let result = try await session.respond(
                    to: prompt, schema: schema, options: options, contextOptions: original.contextOptions
                )
                var json = try JSONValue(json: result.rawContent.jsonString)
                if let redact {
                    json = try JSONValue(json: redact(try json.canonicalString()))
                }
                response = Tape.Response(json: json, outputTokens: result.usage.output.totalTokenCount)
                entries = Array(result.transcriptEntries)
            } else {
                let result = try await session.respond(
                    to: prompt, options: options, contextOptions: original.contextOptions
                )
                response = Tape.Response(
                    text: redact?(result.content) ?? result.content,
                    outputTokens: result.usage.output.totalTokenCount
                )
                entries = Array(result.transcriptEntries)
            }

            var assetIDs: Set<String> = []
            var systemVersion: String?
            for case .response(let entry) in entries {
                assetIDs.formUnion(entry.assetIDs)
                if let value = entry.metadata["systemVersion"] {
                    systemVersion = (try? value.value(String.self)) ?? value.jsonString
                }
            }

            let interaction = Tape.Interaction(
                key: try Canonical.key(for: request),
                request: request,
                response: response,
                provenance: Tape.Provenance(
                    recordedAt: Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded()),
                    systemVersion: systemVersion,
                    assetIDs: assetIDs.sorted(),
                    sampling: options.samplingMode.map(Request.Sampling.init) ?? .greedy
                )
            )
            // The file is rewritten after every interaction, so an interrupted run leaves a
            // valid tape. Written inside the lock: writes can't interleave.
            try storage.withLock { storage in
                storage.tape.interactions.append(interaction)
                try storage.tape.write(to: url)
            }
            return response
        }

        /// The recorded request with the fewest differing parts; ties go to the prompt
        /// that shares the longest beginning.
        private static func closest(to request: Request, in recorded: [Request]) -> Request? {
            recorded.min { a, b in
                let (da, db) = (request.differences(from: a).count, request.differences(from: b).count)
                if da != db { return da < db }
                return request.prompt.commonPrefix(with: a.prompt).count > request.prompt.commonPrefix(with: b.prompt).count
            }
        }

        static func == (lhs: State, rhs: State) -> Bool {
            lhs === rhs
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(self))
        }
    }
}

// MARK: - Errors

/// What a ``Cassette`` throws on its own account. Every message says what to do next.
public enum CassetteError: Error, CustomStringConvertible, LocalizedError {
    /// Replay was asked for and the tape doesn't exist.
    case missingTape(tape: String, path: String)
    /// The tape has no recording of this request.
    case noRecording(tape: String, requested: Cassette.Request, closest: Cassette.Request?, differences: [String])
    /// Recording was asked for while the `CI` environment variable is set.
    case recordingInCI(tape: String)
    /// Recording needs the model, and it can't be used on this machine.
    case modelUnavailable(tape: String, reason: String)
    /// The request uses something tape format v1 can't store.
    case unsupported(String)
    /// The tape was written in a format this version of Assay doesn't read.
    case unsupportedTapeVersion(Int, path: String)
    /// The tape exists but can't be read as one.
    case unreadableTape(path: String, reason: String)
    /// Another cassette in this process is already recording to the same file.
    case tapeInUse(path: String)
    /// `ASSAY_CASSETTE` has a value that isn't `record`, `replay` or `auto`.
    case invalidMode(String)

    public var description: String {
        switch self {
        case .missingTape(let tape, let path):
            return """
                Cassette "\(tape)" has no tape at \(path).
                Record it on a machine with the model: run this test with ASSAY_CASSETTE=record, then commit the file.
                """
        case .noRecording(let tape, let requested, let closest, let differences):
            var lines = ["Cassette \"\(tape)\" has no recording of this request.", "  Requested: \(Self.summary(requested))"]
            if let closest {
                lines.append("  Closest:   \(Self.summary(closest))")
                lines.append("  They differ in: \(differences.joined(separator: ", ")).")
            } else {
                lines.append("  The tape is empty.")
            }
            lines.append("If the request changed on purpose, record the tape again: run this test with ASSAY_CASSETTE=record.")
            return lines.joined(separator: "\n")
        case .recordingInCI(let tape):
            return "Cassette \"\(tape)\" was asked to record, but the CI environment variable is set. "
                + "Tapes are never recorded in CI. Record it locally and commit the file."
        case .modelUnavailable(let tape, let reason):
            return "Cassette \"\(tape)\" can't record: the model is unavailable on this machine (\(reason)). "
                + "Record it on a machine with Apple Intelligence, then commit the file."
        case .unsupported(let what):
            return "Cassettes can't store \(what) yet (tape format v\(Tape.currentVersion))."
        case .unsupportedTapeVersion(let version, let path):
            return "The tape at \(path) has format version \(version); this version of Assay reads version \(Tape.currentVersion). "
                + "Update Assay, or record the tape again with ASSAY_CASSETTE=record."
        case .unreadableTape(let path, let reason):
            return "The tape at \(path) can't be read: \(reason)"
        case .tapeInUse(let path):
            return "Another cassette is already recording to \(path). Give each test its own tape name."
        case .invalidMode(let value):
            return "ASSAY_CASSETTE is \"\(value)\"; it has to be record, replay or auto."
        }
    }

    public var errorDescription: String? {
        description
    }

    private static func summary(_ request: Cassette.Request) -> String {
        var parts = ["prompt \"\(request.prompt)\""]
        if let instructions = request.instructions { parts.append("instructions \"\(instructions)\"") }
        if !request.history.isEmpty { parts.append("\(request.history.count) earlier turns") }
        if request.schema != nil { parts.append("structured") }
        if let sampling = request.options.sampling { parts.append("sampling \(sampling.mode)") }
        if let temperature = request.options.temperature { parts.append("temperature \(temperature)") }
        if let limit = request.options.maximumResponseTokens { parts.append("max \(limit) tokens") }
        return parts.joined(separator: ", ")
    }
}
