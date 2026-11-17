import Foundation
import FoundationModels

extension Cassette {

    /// A request to the model, in the form a cassette stores and matches on.
    ///
    /// Two requests are the same recording only if all of this is equal: the instructions,
    /// the earlier turns, the prompt, the schema and the options. Identifiers that the
    /// framework generates for each transcript entry are left out, because they change on
    /// every run.
    public struct Request: Codable, Sendable, Equatable {
        public var instructions: String?
        /// The earlier turns of the session, oldest first.
        public var history: [Turn]
        public var prompt: String
        /// The schema of the structured output asked for, as canonical JSON text.
        public var schema: String?
        public var options: Options

        public struct Turn: Codable, Sendable, Equatable {
            public enum Role: String, Codable, Sendable {
                case prompt, response
            }
            public var role: Role
            public var text: String
        }

        public struct Options: Codable, Sendable, Equatable {
            public var sampling: Sampling?
            public var temperature: Double?
            public var maximumResponseTokens: Int?
            public var includeSchemaInPrompt: Bool?
        }

        public struct Sampling: Codable, Sendable, Equatable {
            /// "greedy", "top" or "probabilityThreshold".
            public var mode: String
            public var top: Int?
            public var probabilityThreshold: Double?
            public var seed: UInt64?

            static let greedy = Sampling(mode: "greedy")

            init(mode: String, top: Int? = nil, probabilityThreshold: Double? = nil, seed: UInt64? = nil) {
                self.mode = mode
                self.top = top
                self.probabilityThreshold = probabilityThreshold
                self.seed = seed
            }

            init(_ sampling: GenerationOptions.SamplingMode) {
                switch sampling.kind {
                case .greedy:
                    self = .greedy
                case .randomTopK(let top, let seed):
                    self.init(mode: "top", top: top, seed: seed)
                case .randomProbabilityThreshold(let threshold, let seed):
                    self.init(mode: "probabilityThreshold", probabilityThreshold: threshold, seed: seed)
                @unknown default:
                    self.init(mode: String(describing: sampling.kind))
                }
            }
        }

        // The schema is canonical JSON text in memory and nested JSON in the file, so a
        // tape's diff shows the schema instead of one long escaped string.
        private enum CodingKeys: String, CodingKey {
            case instructions, history, prompt, schema, options
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            instructions = try container.decodeIfPresent(String.self, forKey: .instructions)
            history = try container.decode([Turn].self, forKey: .history)
            prompt = try container.decode(String.self, forKey: .prompt)
            schema = try container.decodeIfPresent(JSONValue.self, forKey: .schema)?.canonicalString()
            options = try container.decode(Options.self, forKey: .options)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(instructions, forKey: .instructions)
            try container.encode(history, forKey: .history)
            try container.encode(prompt, forKey: .prompt)
            try container.encodeIfPresent(try schema.map(JSONValue.init(json:)), forKey: .schema)
            try container.encode(options, forKey: .options)
        }
    }
}

extension Cassette.Request {

    /// Reads what the session sent to the executor.
    /// Throws ``CassetteError/unsupported(_:)`` for anything format v1 can't store, rather
    /// than recording a request that would replay differently.
    init(_ request: LanguageModelExecutorGenerationRequest) throws {
        guard request.enabledToolDefinitions.isEmpty else {
            throw CassetteError.unsupported("tools")
        }
        var entries = Array(request.transcript)
        guard case .prompt(let last) = entries.popLast() else {
            throw CassetteError.unsupported("a request that doesn't end with a prompt")
        }

        var instructions: String?
        var history: [Turn] = []
        for entry in entries {
            switch entry {
            case .instructions(let entry):
                guard entry.toolDefinitions.isEmpty else { throw CassetteError.unsupported("tools") }
                instructions = try Self.text(of: entry.segments)
            case .prompt(let entry):
                history.append(Turn(role: .prompt, text: try Self.text(of: entry.segments)))
            case .response(let entry):
                history.append(Turn(role: .response, text: try Self.text(of: entry.segments)))
            case .toolCalls, .toolOutput:
                throw CassetteError.unsupported("tool calls")
            case .reasoning:
                throw CassetteError.unsupported("reasoning entries")
            @unknown default:
                throw CassetteError.unsupported("a transcript entry this version of Assay doesn't know")
            }
        }

        self.instructions = instructions
        self.history = history
        self.prompt = try Self.text(of: last.segments)
        self.schema = try request.schema.map { schema in
            let json = String(decoding: try JSONEncoder().encode(schema), as: UTF8.self)
            return try JSONValue(json: json).canonicalString()
        }
        self.options = Options(
            sampling: request.generationOptions.samplingMode.map(Sampling.init),
            temperature: request.generationOptions.temperature,
            maximumResponseTokens: request.generationOptions.maximumResponseTokens,
            includeSchemaInPrompt: request.contextOptions.includeSchemaInPrompt
        )
    }

    /// A prompt built from several parts arrives as several segments. They are stored one
    /// per line.
    private static func text(of segments: [Transcript.Segment]) throws -> String {
        try parts(of: segments).joined(separator: "\n")
    }

    static func parts(of segments: [Transcript.Segment]) throws -> [String] {
        try segments.map { segment in
            switch segment {
            case .text(let text):
                return text.content
            case .structure(let structure):
                return try JSONValue(json: structure.content.jsonString).canonicalString()
            case .attachment:
                throw CassetteError.unsupported("attachments")
            @unknown default:
                throw CassetteError.unsupported("a transcript segment this version of Assay doesn't know")
            }
        }
    }

    /// The names of the parts in which two requests differ, for the mismatch message.
    func differences(from other: Cassette.Request) -> [String] {
        var differences: [String] = []
        if instructions != other.instructions { differences.append("instructions") }
        if history != other.history { differences.append("earlier turns") }
        if prompt != other.prompt { differences.append("prompt") }
        if schema != other.schema { differences.append("schema") }
        if options != other.options { differences.append("options") }
        return differences
    }
}
