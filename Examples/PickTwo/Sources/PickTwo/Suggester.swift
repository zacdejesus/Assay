// The feature: give the model a numbered list, get back two items that go together, each with
// three suggestions. Two schemas and two strategies, so their effect can be measured.

import Foundation
import FoundationModels

// MARK: - Schemas

/// The obvious schema: a label first, then the picks by index.
@Generable
struct LabelFirstAnswer {
    @Guide(description: "Short label for the choice, for example the kind of day or the cuisine")
    var label: String
    @Guide(description: "Exactly 2 items from the numbered list that go together", .count(2))
    var picks: [IndexPick]
    @Guide(description: "One short sentence on why these two")
    var reason: String
}

@Generable
struct IndexPick {
    @Guide(description: "Index of the chosen item in the numbered list")
    var index: Int
    @Guide(description: "Three suggestions for this item", .count(3))
    var details: [String]
}

/// Fields generate in declaration order, so the order is a prompt: the picks come first, each
/// copies its item's name right before its suggestions, and the label comes last, describing
/// the picks instead of steering them.
@Generable
struct NameFirstAnswer {
    @Guide(description: "Exactly 2 items from the numbered list that go together", .count(2))
    var picks: [NamedPick]
    @Guide(description: "Short label that describes the two chosen items")
    var label: String
    @Guide(description: "One short sentence on why these two")
    var reason: String
}

@Generable
struct NamedPick {
    @Guide(description: "Index of the chosen item in the numbered list")
    var index: Int
    @Guide(description: "The chosen item's name, copied exactly as it appears in the list")
    var name: String
    @Guide(description: "Three suggestions for this item", .count(3))
    var details: [String]
}

// MARK: - Input and output

public struct Item: Sendable, Hashable {
    public let name: String
    /// Days since the user last used it (trained it, cooked with it); nil when never.
    public let daysSinceUsed: Int?

    public init(_ name: String, daysSinceUsed: Int? = nil) {
        self.name = name
        self.daysSinceUsed = daysSinceUsed
    }
}

public struct Suggestion: Codable, Sendable, Equatable {
    public struct Pick: Codable, Sendable, Equatable {
        public let name: String
        public let details: [String]
    }
    public let label: String
    public let picks: [Pick]
    public let reason: String
    /// What the model was shown.
    public let offered: [String]
}

public enum SuggestionError: Error {
    case noValidPick
}

// MARK: - The suggester

public enum Suggester {

    public enum Schema: String, Sendable, CaseIterable {
        /// Label first, picks by index only.
        case labelFirst
        /// Picks first, each copying its item's name; label last.
        case nameFirst
    }

    public enum Strategy: String, Sendable, CaseIterable {
        /// The model gets every item and chooses the category itself.
        case modelChooses
        /// Code chooses the category (``Selection/forToday(_:in:)``); the model gets its items.
        case codeChooses
    }

    /// What a typical app ships: random sampling, so asking again gives something else.
    public static var appOptions: GenerationOptions {
        var options = GenerationOptions(samplingMode: .random(probabilityThreshold: 0.9), temperature: 0.7)
        options.maximumResponseTokens = 512
        return options
    }

    /// What the tests record with: greedy, so a tape holds the model's most likely answer and
    /// a drift report compares models, not dice.
    public static var greedy: GenerationOptions {
        var options = GenerationOptions(samplingMode: .greedy)
        options.maximumResponseTokens = 512
        return options
    }

    /// The recommended setup: ``Schema/nameFirst`` and ``Strategy/codeChooses``.
    public static func suggest(
        _ items: [Item],
        in domain: Domain,
        model: some LanguageModel,
        schema: Schema = .nameFirst,
        strategy: Strategy = .codeChooses,
        options: GenerationOptions = greedy
    ) async throws -> Suggestion {
        let offered = strategy == .codeChooses ? Selection.forToday(items, in: domain) : items.map(\.name)
        let session = LanguageModelSession(model: model, instructions: domain.instructions)
        let prompt = domain.prompt(offered)

        let label: String, reason: String, raw: [(index: Int, name: String?, details: [String])]
        switch schema {
        case .labelFirst:
            let answer = try await session.respond(to: prompt, generating: LabelFirstAnswer.self, options: options).content
            (label, reason) = (answer.label, answer.reason)
            raw = answer.picks.map { ($0.index, nil, $0.details) }
        case .nameFirst:
            let answer = try await session.respond(to: prompt, generating: NameFirstAnswer.self, options: options).content
            (label, reason) = (answer.label, answer.reason)
            raw = answer.picks.map { ($0.index, $0.name, $0.details) }
        }

        let picks = resolve(raw, offered: offered)
        guard !picks.isEmpty else { throw SuggestionError.noValidPick }
        return Suggestion(label: label, picks: picks, reason: reason, offered: offered)
    }

    /// Maps indices back to names. Drops indices out of range, repeated ones, and picks whose
    /// copied name disagrees with their index. Keeps at most 2 picks and 3 details each.
    static func resolve(_ raw: [(index: Int, name: String?, details: [String])], offered: [String]) -> [Suggestion.Pick] {
        var seen = Set<Int>()
        var picks: [Suggestion.Pick] = []
        for pick in raw where offered.indices.contains(pick.index) && seen.insert(pick.index).inserted {
            if let name = pick.name, !names(name, offered[pick.index]) { continue }
            picks.append(.init(name: offered[pick.index], details: Array(pick.details.prefix(3))))
            if picks.count == 2 { break }
        }
        return picks
    }

    /// The copied name is the item's, allowing case, accents and trailing noise
    /// ("Legs: legs/abs" names "Legs").
    static func names(_ copied: String, _ item: String) -> Bool {
        let (copied, item) = (fold(copied), fold(item))
        return copied == item || copied.hasPrefix(item + " ")
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}

// MARK: - Deciding in code

public enum Selection {
    /// The items of one category, chosen in code: the category of the least recently used item
    /// whose category has at least 2 items in the list (never used counts as least recent; ties
    /// keep list order). Least recently used first. Without such a category (names code can't
    /// place), every item, least recently used first.
    public static func forToday(_ items: [Item], in domain: Domain) -> [String] {
        let ordered = items.enumerated().sorted { a, b in
            let x = a.element.daysSinceUsed ?? .max, y = b.element.daysSinceUsed ?? .max
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element.name)
        let categories = ordered.map(domain.category(of:))
        var count: [String: Int] = [:]
        for case let category? in categories { count[category, default: 0] += 1 }
        guard let today = categories.lazy.compactMap({ $0 }).first(where: { count[$0, default: 0] >= 2 }) else {
            return ordered
        }
        return zip(ordered, categories).filter { $0.1 == today }.map(\.0)
    }
}

// MARK: - Scoring

public enum Score {
    /// Both picks in the same known category; nil when either can't be placed.
    public static func coherent(_ suggestion: Suggestion, in domain: Domain) -> Bool? {
        guard suggestion.picks.count == 2,
              let a = domain.category(of: suggestion.picks[0].name),
              let b = domain.category(of: suggestion.picks[1].name) else { return nil }
        return a == b
    }

    /// The category of the picks, when they share one.
    public static func category(_ suggestion: Suggestion, in domain: Domain) -> String? {
        let categories = Set(suggestion.picks.compactMap { domain.category(of: $0.name) })
        return categories.count == 1 && suggestion.picks.count == 2 ? categories.first : nil
    }
}
