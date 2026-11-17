// The tape: what a cassette file holds. Format v1, JSON.
// Design: docs/decisions/0005-cassette.md

import CryptoKit
import Foundation
import FoundationModels

let assayVersion = "0.2.0-dev"

/// The file on disk.
struct Tape: Codable, Sendable {
    static let currentVersion = 1

    /// The format version. A tape with another version is rejected, not guessed at.
    var version = Tape.currentVersion
    /// The Assay version that wrote the file.
    var assay = assayVersion
    /// The hardware model of the machine that recorded it, e.g. "Mac16,1".
    var machine: String?
    var interactions: [Interaction] = []

    struct Interaction: Codable, Sendable {
        /// SHA-256 of the request's canonical JSON. What replay matches on.
        var key: String
        var request: Cassette.Request
        var response: Response
        var provenance: Provenance
    }

    /// What the model answered. Exactly one of `text` and `json` is set.
    struct Response: Codable, Sendable {
        var text: String?
        /// Structured output, stored as real JSON so a diff of the tape is readable.
        var json: JSONValue?
        var outputTokens: Int

        /// The text the executor sends back to the session.
        var emitted: String {
            get throws {
                if let json { return try json.canonicalString() }
                return text ?? ""
            }
        }
    }

    /// Where an answer came from. M4 (the drift report) depends on this.
    struct Provenance: Codable, Sendable {
        var recordedAt: Date
        /// e.g. "Version 27.2 (Build 26B123)", as the model reported it.
        var systemVersion: String?
        /// The model assets that produced the answer, sorted.
        var assetIDs: [String]
        /// The sampling actually used, which is greedy when the request didn't choose one.
        var sampling: Cassette.Request.Sampling
        /// How long the model took to answer, in seconds. Noisy: the first request in a
        /// process is several times slower than the next.
        var seconds: Double?
    }

    // MARK: Reading and writing

    static func read(from url: URL) throws -> Tape {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw CassetteError.unreadableTape(path: url.path, reason: error.localizedDescription)
        }
        struct Header: Decodable { var version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let header = try decoder.decode(Header.self, from: data)
            guard header.version == currentVersion else {
                throw CassetteError.unsupportedTapeVersion(header.version, path: url.path)
            }
            return try decoder.decode(Tape.self, from: data)
        } catch let error as CassetteError {
            throw error
        } catch {
            throw CassetteError.unreadableTape(path: url.path, reason: String(describing: error))
        }
    }

    /// Writes the whole tape, atomically: a reader never sees half a file.
    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(self)
        data.append(UInt8(ascii: "\n"))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: Generations

    /// The models that produced this tape's answers. Normally one.
    var models: Set<[String]> {
        Set(interactions.map(\.provenance.assetIDs))
    }

    /// A short name for the model that produced the tape, usable in a file name:
    /// "27.2-26B123-1a2b3c4d" (system version, build, digest of the asset IDs).
    var generationLabel: String {
        guard let provenance = interactions.first?.provenance else { return "empty" }
        var label = "unknown"
        if let version = provenance.systemVersion,
           let match = version.firstMatch(of: /Version ([0-9.]+) \(Build ([0-9A-Za-z]+)\)/) {
            label = "\(match.1)-\(match.2)"
        }
        let digest = SHA256.hash(data: Data(provenance.assetIDs.joined(separator: "\n").utf8))
        return label + "-" + digest.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Where an older generation of the tape at `url` is kept:
    /// `__Cassettes__/generations/<name>/<label>.json`.
    func archiveURL(besides url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("generations")
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent)
            .appendingPathComponent("\(generationLabel).json")
    }

    /// Keeps this tape as an older generation if it was recorded from a different model
    /// than `assetIDs`. Recording again from the same model just replaces the tape.
    /// Returns where it was written, if it was.
    @discardableResult
    func archive(besides url: URL, ifModelDiffersFrom assetIDs: [String]) throws -> URL? {
        guard !interactions.isEmpty, models != [assetIDs] else { return nil }
        let destination = archiveURL(besides: url)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return destination }
        try write(to: destination)
        return destination
    }

    static var currentMachine: String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

// MARK: - Canonical JSON

/// Any JSON value. Used to keep schemas and structured answers as nested JSON in the tape,
/// and to give them one canonical text form: `GeneratedContent.jsonString` and an encoded
/// `GenerationSchema` don't keep a stable key order from one run to the next.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(json: String) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Compact JSON with sorted keys: the same value always gives the same text.
    func canonicalString() throws -> String {
        String(decoding: try Canonical.encode(self), as: UTF8.self)
    }
}

enum Canonical {
    /// Compact, sorted-key JSON. The input to the request key.
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    /// `Hasher` is seeded per process, so it can't name anything that outlives one. This is
    /// a real digest.
    static func key(for request: Cassette.Request) throws -> String {
        SHA256.hash(data: try encode(request)).map { String(format: "%02x", $0) }.joined()
    }
}
