// A domain: what the items are, how they group, and how the feature asks about them.

import FoundationModels

/// Items that go together form a category: the kinds of gym day, the cuisines.
public struct Domain: Sendable, Hashable {
    public struct Category: Sendable, Hashable {
        public let name: String
        /// Lowercased item names that belong to it.
        public let members: [String]
    }

    public let id: String
    /// In the order the instructions list them.
    public let categories: [Category]
    let role: String
    let itemKind: String
    let categoryKind: String
    let detailRule: String
    let question: String

    /// The category an item belongs to, or nil for names code can't place ("Upper body").
    public func category(of item: String) -> String? {
        let name = item.lowercased().trimmingCharacters(in: .whitespaces)
        return categories.first { $0.members.contains(name) }?.name
    }

    /// The same domain with its categories listed in another order in the instructions.
    public func listing(_ order: [String]) -> Domain {
        Domain(id: id, categories: order.compactMap { name in categories.first { $0.name == name } },
               role: role, itemKind: itemKind, categoryKind: categoryKind, detailRule: detailRule, question: question)
    }

    // MARK: Prompts

    var instructions: Instructions {
        let table = categories.map { "\($0.name): \($0.members.joined(separator: ", "))" }.joined(separator: "; ")
        return Instructions {
            role
            "From the numbered list of AVAILABLE \(itemKind), choose EXACTLY 2 that belong to the same \(categoryKind) (\(table))."
            "Refer to each one by its index."
            detailRule
        }
    }

    func prompt(_ names: [String]) -> String {
        let numbered = names.enumerated().map { "\($0.offset)=\($0.element)" }.joined(separator: ", ")
        return "Available \(itemKind): \(numbered)\n\n\(question)"
    }

    // MARK: The two domains

    public static let gym = Domain(
        id: "gym",
        categories: [
            Category(name: "push", members: ["chest", "shoulders", "triceps"]),
            Category(name: "pull", members: ["back", "biceps", "forearms"]),
            Category(name: "legs", members: ["legs", "glutes", "calves", "abs", "core"]),
        ],
        role: "You plan a gym session.",
        itemKind: "muscle groups",
        categoryKind: "kind of training day",
        detailRule: "For each chosen group, list 3 exercises that train that group and no other.",
        question: "Which two groups should I train today, with 3 exercises for each?"
    )

    public static let meals = Domain(
        id: "meals",
        categories: [
            Category(name: "italian", members: ["pasta", "tomatoes", "basil", "mozzarella"]),
            Category(name: "mexican", members: ["tortillas", "black beans", "avocado", "lime"]),
            Category(name: "japanese", members: ["rice", "nori", "tofu", "miso"]),
        ],
        role: "You plan a home-cooked dinner.",
        itemKind: "ingredients",
        categoryKind: "cuisine",
        detailRule: "For each chosen ingredient, list 3 dishes of that cuisine built around that ingredient.",
        question: "Which two ingredients should I cook with tonight, with 3 dishes for each?"
    )
}
