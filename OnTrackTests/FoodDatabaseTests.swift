import XCTest
@testable import OnTrack

/// Runnable check for the bundled food search engine — mirrors FoodDatabase.selfCheck()
/// but through XCTest so it runs in CI/`xcodebuild test` rather than only a debug tap.
final class FoodDatabaseTests: XCTestCase {
    func testBundleLoaded() {
        XCTAssertGreaterThan(FoodDatabase.all.count, 12_000, "foods.json should be bundled and decode")
    }

    func testSelfCheckPasses() {
        let failures = FoodDatabase.selfCheck()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "; "))
    }

    func testAliasExpansionFindsColloquialNames() {
        let hits = FoodDatabase.search("chapati")
        XCTAssertTrue(hits.contains { $0.n == "Bread, chappatti or roti" },
                      "alias 'chapati' -> 'chappatti' should surface the FNDDS roti entry")
    }

    func testExactNameRanksAboveSubstringMatch() {
        let hits = FoodDatabase.search("samosa")
        XCTAssertEqual(hits.first?.n, "Samosa")
    }

    func testTrueGapReturnsEmptySoAIFallbackCanEngage() {
        XCTAssertTrue(FoodDatabase.search("karahi").isEmpty)
    }

    /// Regression: "roti" is a literal prefix of "rotisserie", so a naive prefix-match
    /// ranking lets rotisserie chicken items outrank the actual roti bread entry.
    func testWholeWordMatchOutranksPrefixOfLongerWord() {
        let hits = FoodDatabase.search("roti")
        XCTAssertEqual(hits.first?.n, "Bread, chappatti or roti")
    }

    func testGroupedAlphabeticallyCoversEveryFoodSortedWithHashLast() {
        let groups = FoodDatabase.groupedAlphabetically
        XCTAssertEqual(groups.reduce(0) { $0 + $1.foods.count }, FoodDatabase.all.count,
                       "every bundled food must appear in exactly one letter group")
        if groups.contains(where: { $0.letter == "#" }) {
            XCTAssertEqual(groups.last?.letter, "#", "non-letter-first-character foods sort last")
        }
        for group in groups where group.letter != "#" {
            let names = group.foods.map(\.n)
            XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                           "group '\(group.letter)' must be alphabetically sorted")
        }
    }
}
