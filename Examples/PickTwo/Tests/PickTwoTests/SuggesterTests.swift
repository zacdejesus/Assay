// The code around the model: no model needed.

@testable import PickTwo
import Testing

@Suite("Code around the model")
struct SuggesterTests {

    @Test("The least recently used category with two items is chosen")
    func leastRecent() {
        let items = [Item("Chest", daysSinceUsed: 3), Item("Triceps", daysSinceUsed: 3), Item("Legs", daysSinceUsed: 9), Item("Abs", daysSinceUsed: 9)]
        #expect(Selection.forToday(items, in: .gym) == ["Legs", "Abs"])
    }

    @Test("A category with one item is skipped, and never used counts as least recent")
    func skipsLoneItem() {
        let items = [Item("Pasta", daysSinceUsed: 8), Item("Tofu", daysSinceUsed: 5), Item("Miso"), Item("Lime", daysSinceUsed: 3)]
        #expect(Selection.forToday(items, in: .meals) == ["Miso", "Tofu"])
    }

    @Test("Names code can't place are left out when a category exists, and kept when none does")
    func unknownNames() {
        #expect(Selection.forToday([Item("Upper body", daysSinceUsed: 5), Item("Legs", daysSinceUsed: 4), Item("Core", daysSinceUsed: 4)], in: .gym) == ["Legs", "Core"])
        #expect(Selection.forToday([Item("Upper body", daysSinceUsed: 5), Item("Legs", daysSinceUsed: 7)], in: .gym) == ["Legs", "Upper body"])
    }

    @Test("Resolving drops bad indices, repeats and names that disagree with their index")
    func resolve() {
        let offered = ["Back", "Biceps", "Legs"]
        let picks = Suggester.resolve([
            (index: 9, name: nil, details: ["x"]),
            (index: 0, name: "Back", details: ["a", "b", "c", "d"]),
            (index: 0, name: "Back", details: ["a"]),
            (index: 1, name: "Legs", details: ["a"]),
            (index: 2, name: "Legs: legs/abs", details: ["a"]),
        ], offered: offered)
        #expect(picks.map(\.name) == ["Back", "Legs"])
        #expect(picks[0].details == ["a", "b", "c"])
    }

    @Test("Coherence is scored from the domain's categories")
    func coherence() {
        func suggestion(_ a: String, _ b: String) -> Suggestion {
            Suggestion(label: "", picks: [.init(name: a, details: []), .init(name: b, details: [])], reason: "", offered: [])
        }
        #expect(Score.coherent(suggestion("Back", "Biceps"), in: .gym) == true)
        #expect(Score.coherent(suggestion("Back", "Abs"), in: .gym) == false)
        #expect(Score.coherent(suggestion("Upper body", "Legs"), in: .gym) == nil)
        #expect(Score.category(suggestion("Rice", "Nori"), in: .meals) == "japanese")
    }
}
