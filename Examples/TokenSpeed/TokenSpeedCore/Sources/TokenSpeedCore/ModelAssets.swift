import FoundationModels

/// Which model produced a response, as the framework reports it.
///
/// Apple's API has no model name. What a response carries is a list of asset identifiers,
/// such as `com.apple.fm.language.instruct_3b.fm_api_generic_3b?variant=generic_sparse_16.1000.0.13.103404,0`.
/// The app shows them as they are, minus the prefix they share, instead of guessing which
/// part is the name.
public enum ModelAssets {

    /// The asset identifiers in a response's transcript entries, sorted and without
    /// duplicates. Sorted because the framework returns them in a different order from one
    /// response to the next.
    public static func identifiers(in entries: some Sequence<Transcript.Entry>) -> [String] {
        var identifiers: Set<String> = []
        for entry in entries {
            guard case .response(let response) = entry else { continue }
            identifiers.formUnion(response.assetIDs)
        }
        return identifiers.sorted()
    }

    /// The identifiers without the dot-separated prefix they all share, for display.
    /// `["a.b.one?v=1", "a.b.two?v=2"]` becomes `["one?v=1", "two?v=2"]`.
    public static func labels(for identifiers: [String]) -> [String] {
        // Only the part before "?" is a dotted name; versions after it contain dots too.
        let names = identifiers.map { $0.prefix { $0 != "?" }.split(separator: ".", omittingEmptySubsequences: false) }
        guard var shared = names.first?.dropLast() else { return [] }
        for name in names.dropFirst() {
            let common = zip(shared, name.dropLast()).prefix { $0 == $1 }.count
            shared = shared.prefix(common)
        }
        let prefixLength = shared.reduce(0) { $0 + $1.count + 1 }
        return identifiers.map { String($0.dropFirst(prefixLength)) }
    }
}
