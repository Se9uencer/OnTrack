import Foundation

/// One portion definition for a bundled food: a human label ("1 medium roti (40 g)") and
/// its gram weight. Decoded from a 2-element JSON array, e.g. ["1 medium roti", 40].
struct FoodPortion: Codable, Hashable {
    let label: String
    let grams: Double

    init(label: String, grams: Double) {
        self.label = label
        self.grams = grams
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        label = try c.decode(String.self)
        grams = try c.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(label)
        try c.encode(grams)
    }
}

/// A row from the bundled USDA FoodData Central database (FNDDS + Foundation + SR Legacy).
/// All macro/micronutrient values are PER 100g, matching the on-disk foods.json.
/// Public-domain data only — see build_food_db.py for why Open Food Facts is excluded.
struct BundledFood: Codable, Identifiable, Hashable {
    let id: String
    let n: String
    let s: String // "fndds" | "foundation" | "srlegacy"
    let p: [FoodPortion]
    let kcal: Double
    let protein: Double?
    let carb: Double?
    let fat: Double?
    let satFat: Double?
    let transFat: Double?
    let chol: Double?
    let sodium: Double?
    let fiber: Double?
    let sugar: Double?
    let vitA: Double?
    let vitC: Double?
    let calcium: Double?
    let iron: Double?
    let potassium: Double?

    var name: String { n }
    var portions: [FoodPortion] { p }

    /// Bundled foods always report per-100g, so the search result's "1 serving" is 100g —
    /// consistent with how searchUSDA already represents Foundation/SR Legacy results.
    /// The richer named portions (portions) drive the unit picker, not this base serving.
    func toSearchResult() -> FoodSearchResult {
        FoodSearchResult(name: n, brand: nil, source: "fndds", barcode: nil, fdcId: id,
                          servingSize: 100, servingUnit: "g",
                          calories: kcal, protein: protein ?? 0, carbs: carb ?? 0, fat: fat ?? 0)
    }
}

enum FoodDatabase {
    static let all: [BundledFood] = {
        guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([BundledFood].self, from: data)
        else { return [] }
        return list
    }()

    private static let byID: [String: BundledFood] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// The full bundle, grouped by first letter (A-Z, "#" for anything else) and sorted
    /// alphabetically within each group. Computed once — this backs the "All Foods" browse
    /// list, not live search, so it doesn't need to be index-fast, just built once.
    static let groupedAlphabetically: [(letter: String, foods: [BundledFood])] = {
        let sorted = all.sorted { $0.n.localizedCaseInsensitiveCompare($1.n) == .orderedAscending }
        let groups = Dictionary(grouping: sorted) { food -> String in
            guard let first = food.n.first, first.isLetter else { return "#" }
            return String(first).uppercased()
        }
        return groups.keys.sorted { a, b in
            if a == "#" { return false }
            if b == "#" { return true }
            return a < b
        }.map { letter in (letter, groups[letter] ?? []) }
    }()

    /// alias -> expansion search terms, e.g. "roti": ["chappatti"]. See build_food_db.py's
    /// sibling authoring notes in aliases.json for why some colloquial dishes are deliberately
    /// absent (they have no bundle equivalent, and should fall through to the AI/manual path).
    private static let aliases: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "aliases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return map
    }()

    private struct Indexed {
        let food: BundledFood
        let lowerName: String
        let words: [String]
    }

    // Precomputed once at first use so search() never re-lowercases/re-splits per keystroke.
    private static let indexed: [Indexed] = all.map { food in
        let lower = food.n.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return Indexed(food: food, lowerName: lower, words: words)
    }

    static func find(_ id: String) -> BundledFood? { byID[id] }

    static func search(_ query: String, limit: Int = 30) -> [BundledFood] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var bestScore: [String: Int] = [:] // food id -> best score across expanded queries
        for q in expandedQueries(trimmed) {
            let queryTokens = q.split(separator: " ").map(String.init)
            for item in indexed {
                let s = score(item, query: q, queryTokens: queryTokens)
                guard s > 0 else { continue }
                if let existing = bestScore[item.food.id], existing >= s { continue }
                bestScore[item.food.id] = s
            }
        }

        return bestScore
            .compactMap { id, s in byID[id].map { (food: $0, score: s) } }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.food.n.count != b.food.n.count { return a.food.n.count < b.food.n.count }
                return sourceRank(a.food.s) < sourceRank(b.food.s)
            }
            .prefix(limit)
            .map(\.food)
    }

    private static func sourceRank(_ s: String) -> Int {
        switch s {
        case "fndds": return 0
        case "foundation": return 1
        default: return 2 // srlegacy
        }
    }

    private static func expandedQueries(_ query: String) -> [String] {
        var queries = [query]
        if let expansion = aliases[query] { queries.append(contentsOf: expansion) }
        let tokens = query.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            for token in tokens {
                if let expansion = aliases[token] { queries.append(contentsOf: expansion) }
            }
        }
        return queries
    }

    private static func score(_ item: Indexed, query: String, queryTokens: [String]) -> Int {
        if item.lowerName == query { return 1000 }
        if item.lowerName.hasPrefix(query) { return 800 }
        // Whole-word matches ("roti" == word "roti" in "chappatti or roti") must outrank a
        // mere prefix-of-a-longer-word match ("roti" is a prefix of "rotisserie") — otherwise
        // "rotisserie" results flood a search for "roti".
        if !queryTokens.isEmpty, queryTokens.allSatisfy({ qt in item.words.contains(qt) }) {
            return 700
        }
        if !queryTokens.isEmpty, queryTokens.allSatisfy({ qt in item.words.contains { $0.hasPrefix(qt) } }) {
            return 500
        }
        if item.lowerName.contains(query) { return 300 }
        return 0
    }
}

#if DEBUG
extension FoodDatabase {
    /// Runnable check: real dishes must be findable, and dishes with no bundle equivalent
    /// must come back empty so the AI-estimate/manual-entry fallback engages honestly instead
    /// of silently matching an unrelated food. Wired to a debug-only Settings row.
    static func selfCheck() -> [String] {
        var failures: [String] = []
        let mustFind = ["roti", "biryani", "samosa", "chicken breast", "daal", "chapati", "paneer"]
        for q in mustFind where search(q).isEmpty {
            failures.append("'\(q)' expected results, got none")
        }
        let mustBeEmpty = ["karahi", "haleem", "nihari"]
        for q in mustBeEmpty {
            let hits = search(q)
            if !hits.isEmpty {
                failures.append("'\(q)' expected empty (no bundle equivalent), got \(hits.count) hits")
            }
        }
        return failures
    }
}
#endif
