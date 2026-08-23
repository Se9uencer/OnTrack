import XCTest
import SwiftData
@testable import OnTrack

/// Opens a store that was seeded (and saved) under the pre-1.2.0 schema — before DiaryEntry
/// had grams/portionLabel — with the CURRENT schema, and confirms SwiftData's automatic
/// lightweight migration doesn't lose data or change historical totals. Live users are on
/// the App Store, so this is the gate for the schema change in FOOD_DB_PLAN.md Phase 3.
final class LightweightMigrationTests: XCTestCase {
    @MainActor
    func testPreExistingStoreOpensWithUnchangedTotals() throws {
        let path = "/private/tmp/claude-501/-Users-ibrahimansari-Fitness-App/d44bbdf3-d2b9-4052-91b9-8a8dafad43d0/scratchpad/migration_fixture.store"
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "fixture missing — regenerate via the pre-Phase-3 seed step before running this test")

        let schema = Schema([FoodItem.self, DiaryEntry.self])
        let config = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: path))
        let container = try ModelContainer(for: schema, configurations: config) // must not throw

        let entries = try container.mainContext.fetch(FetchDescriptor<DiaryEntry>())
        XCTAssertEqual(entries.count, 2, "both pre-1.2.0 diary rows must survive the migration")

        let total = entries.reduce(0.0) { $0 + $1.calories }
        XCTAssertEqual(total, 508.3, accuracy: 0.01,
                       "historical calorie total must be byte-identical to what was seeded pre-migration")

        for entry in entries {
            XCTAssertEqual(entry.grams, 0, "new field defaults for rows that predate it")
            XCTAssertEqual(entry.portionLabel, "", "new field defaults for rows that predate it")
            XCTAssertNotNil(entry.food, "the food relationship must still resolve")
        }
    }
}
