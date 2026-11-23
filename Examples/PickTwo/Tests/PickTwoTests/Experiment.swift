// Live experiment: which setup gives coherent picks that follow the user's history?
// Needs Apple Intelligence; a few minutes per domain. Numbers vary run to run (random sampling).
//
//   PICKTWO_EXPERIMENT=1 swift test --filter "Experiment/gym"
//   PICKTWO_EXPERIMENT=1 swift test --filter "Experiment/meals"

import Foundation
import FoundationModels
import PickTwo
import Testing

let experimenting = ProcessInfo.processInfo.environment["PICKTWO_EXPERIMENT"] == "1"

struct Variant: Sendable, CustomStringConvertible {
    let name: String
    let schema: Suggester.Schema
    let strategy: Suggester.Strategy
    var reversedTable = false
    var description: String { name }

    static let all = [
        Variant(name: "label-first, model chooses", schema: .labelFirst, strategy: .modelChooses),
        Variant(name: "label-first, model chooses, table reversed", schema: .labelFirst, strategy: .modelChooses, reversedTable: true),
        Variant(name: "name-first, model chooses", schema: .nameFirst, strategy: .modelChooses),
        Variant(name: "name-first, code chooses", schema: .nameFirst, strategy: .codeChooses),
    ]
}

@Suite("Experiment (live)", .serialized, .enabled(if: experimenting))
struct Experiment {
    static let samples = 5

    @Test func gym() async throws { try await run(Case.gym) }

    /// Are the exercises under the group they train? A keyword check, gym only: shoulder
    /// exercises under chest, leg exercises under upper-body groups.
    @Test func gymDetails() async throws {
        let shoulder = ["overhead press", "lateral raise", "front raise", "face pull", "rear delt", "shoulder press", "arnold"]
        // Not deadlifts: they train the back too, so they aren't clearly misplaced under Back.
        let leg = ["squat", "lunge", "leg press", "calf", "leg curl", "leg extension"]
        let upper: Set<String> = ["chest", "back", "biceps", "triceps", "shoulders", "forearms"]
        for schema in Suggester.Schema.allCases {
            var n = 0, onTarget = 0
            for c in Case.gym {
                for _ in 0..<Self.samples {
                    guard let s = try? await Suggester.suggest(c.items, in: c.domain, model: SystemLanguageModel.default,
                                                               schema: schema, strategy: .codeChooses, options: Suggester.appOptions) else { continue }
                    n += 1
                    let off = s.picks.contains { pick in
                        let group = pick.name.lowercased(), details = pick.details.joined(separator: " | ").lowercased()
                        return (group == "chest" && shoulder.contains { details.contains($0) })
                            || (upper.contains(group) && leg.contains { details.contains($0) })
                    }
                    onTarget += off ? 0 : 1
                    print("DETAILS \(schema) \(c) | " + s.picks.map { "\($0.name): \($0.details.joined(separator: ", "))" }.joined(separator: " | "))
                }
            }
            print("RESULT gym details | \(schema), code chooses | exercises under their group \(onTarget)/\(n)")
        }
    }
    @Test func meals() async throws { try await run(Case.meals) }

    func run(_ cases: [Case]) async throws {
        for variant in Variant.all {
            var n = 0, full = 0, scorable = 0, coherent = 0, expected = 0, withExpected = 0
            var categories: [String: Int] = [:]
            for c in cases {
                let domain = variant.reversedTable ? c.domain.listing(c.domain.categories.map(\.name).reversed()) : c.domain
                // What a user would expect: the category code picks from the history.
                let due = Selection.forToday(c.items, in: c.domain).first.flatMap(c.domain.category(of:))
                for _ in 0..<Self.samples {
                    n += 1
                    guard let s = try? await Suggester.suggest(c.items, in: domain, model: SystemLanguageModel.default,
                                                               schema: variant.schema, strategy: variant.strategy,
                                                               options: Suggester.appOptions) else { continue }
                    full += s.picks.count == 2 ? 1 : 0
                    if let ok = Score.coherent(s, in: c.domain) { scorable += 1; coherent += ok ? 1 : 0 }
                    let category = Score.category(s, in: c.domain)
                    categories[category ?? "none", default: 0] += 1
                    if let due { withExpected += 1; expected += category == due ? 1 : 0 }
                    print("SAMPLE \(c) | \(variant) | \(s.picks.map(\.name).joined(separator: " + ")) | \(s.label)")
                }
            }
            let spread = categories.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            print("RESULT \(cases[0].domain.id) | \(variant) | two picks \(full)/\(n) | coherent \(coherent)/\(scorable) | due category \(expected)/\(withExpected) | \(spread)")
        }
    }
}
