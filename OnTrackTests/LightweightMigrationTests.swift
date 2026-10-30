import XCTest
import SwiftData
@testable import OnTrack

/// Opens a store that was seeded (and saved) under the pre-1.2.0 schema — before DiaryEntry
/// had grams/portionLabel — with the CURRENT schema, and confirms SwiftData's automatic
/// lightweight migration doesn't lose data or change historical totals. Live users are on
/// the App Store, so this is the gate for the schema change in FOOD_DB_PLAN.md Phase 3.
///
/// The fixture (`Fixtures/LightweightMigrationV1.store`) is a real store written under the
/// exact pre-1.2.0 FoodItem/DiaryEntry declarations (git commit 60d7f15^), bundled as a test
/// resource rather than regenerated at runtime — SwiftData can't declare two `DiaryEntry`
/// types in one module, so the old schema can't be recreated in-process.
final class LightweightMigrationTests: XCTestCase {
    @MainActor
    func testPreExistingStoreOpensWithUnchangedTotals() throws {
        let bundledURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "LightweightMigrationV1", withExtension: "store"),
            "fixture not bundled with OnTrackTests — check it's listed under the OnTrackTests target's Resources build phase")

        // Copy to a fresh scratch location per run so SwiftData's open (which may write
        // -wal/-shm sidecars) never touches the committed fixture.
        let workingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("LightweightMigrationV1.store")
        try FileManager.default.createDirectory(at: workingURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: bundledURL, to: workingURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workingURL.deletingLastPathComponent())
        }

        let schema = Schema([FoodItem.self, DiaryEntry.self])
        let config = ModelConfiguration(schema: schema, url: workingURL)
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
