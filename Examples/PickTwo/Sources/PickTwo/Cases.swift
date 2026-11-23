// The cases every test and experiment runs: lists a user could have, after an app has already
// removed what was used today or yesterday.

public struct Case: Sendable, Hashable, CustomStringConvertible {
    public let id: String
    public let domain: Domain
    public let items: [Item]
    public var description: String { "\(domain.id)-\(id)" }

    public static let all = gym + meals

    public static let gym: [Case] = [
        Case(id: "all-fresh", domain: .gym, items: ["Chest", "Back", "Shoulders", "Biceps", "Triceps", "Legs", "Abs"].map { Item($0) }),
        Case(id: "legs-least-recent", domain: .gym, items: [Item("Chest", daysSinceUsed: 3), Item("Back", daysSinceUsed: 4), Item("Shoulders", daysSinceUsed: 3), Item("Biceps", daysSinceUsed: 4), Item("Triceps", daysSinceUsed: 3), Item("Legs", daysSinceUsed: 9), Item("Abs", daysSinceUsed: 9)]),
        Case(id: "pull-least-recent", domain: .gym, items: [Item("Chest", daysSinceUsed: 2), Item("Back", daysSinceUsed: 7), Item("Shoulders", daysSinceUsed: 2), Item("Biceps", daysSinceUsed: 7), Item("Legs", daysSinceUsed: 4), Item("Abs", daysSinceUsed: 4)]),
        Case(id: "no-push", domain: .gym, items: [Item("Back", daysSinceUsed: 5), Item("Biceps", daysSinceUsed: 5), Item("Legs", daysSinceUsed: 3), Item("Abs", daysSinceUsed: 3)]),
        Case(id: "one-pair", domain: .gym, items: [Item("Back", daysSinceUsed: 5), Item("Biceps", daysSinceUsed: 5), Item("Chest", daysSinceUsed: 8), Item("Legs", daysSinceUsed: 3)]),
        Case(id: "own-names", domain: .gym, items: [Item("Upper body", daysSinceUsed: 3), Item("Legs", daysSinceUsed: 4), Item("Core", daysSinceUsed: 4)]),
    ]

    public static let meals: [Case] = [
        Case(id: "all-fresh", domain: .meals, items: ["Pasta", "Tortillas", "Tomatoes", "Rice", "Black beans", "Nori", "Avocado", "Tofu"].map { Item($0) }),
        Case(id: "japanese-least-recent", domain: .meals, items: [Item("Pasta", daysSinceUsed: 2), Item("Tortillas", daysSinceUsed: 3), Item("Tomatoes", daysSinceUsed: 2), Item("Rice", daysSinceUsed: 9), Item("Black beans", daysSinceUsed: 3), Item("Miso", daysSinceUsed: 9)]),
        Case(id: "mexican-least-recent", domain: .meals, items: [Item("Pasta", daysSinceUsed: 2), Item("Basil", daysSinceUsed: 2), Item("Tortillas", daysSinceUsed: 8), Item("Rice", daysSinceUsed: 4), Item("Avocado", daysSinceUsed: 8), Item("Tofu", daysSinceUsed: 4)]),
        Case(id: "no-italian", domain: .meals, items: [Item("Tortillas", daysSinceUsed: 5), Item("Avocado", daysSinceUsed: 5), Item("Rice", daysSinceUsed: 3), Item("Nori", daysSinceUsed: 3)]),
        Case(id: "one-pair", domain: .meals, items: [Item("Tofu", daysSinceUsed: 5), Item("Miso", daysSinceUsed: 5), Item("Pasta", daysSinceUsed: 8), Item("Lime", daysSinceUsed: 3)]),
        Case(id: "own-names", domain: .meals, items: [Item("Leftover chicken", daysSinceUsed: 1), Item("Rice", daysSinceUsed: 4), Item("Nori", daysSinceUsed: 4)]),
    ]
}
