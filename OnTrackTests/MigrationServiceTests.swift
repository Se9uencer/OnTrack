import XCTest
import SwiftData
@testable import OnTrack

/// Runnable check for MigrationService.dedupeFoodItems — the pass that merges the
/// pre-1.2.0 duplicate FoodItem rows on a live, populated store. This is a data-loss-risk
/// path (repoints DiaryEntry relationships and deletes rows), so it gets a real test rather
/// than a debug print.
final class MigrationServiceTests: XCTestCase {
    @MainActor
    func testDedupeMergesDuplicateFoodItemsAndRepointsDiaryEntries() throws {
        let schema = Schema([FoodItem.self, DiaryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = container.mainContext

        // Seed 3 duplicate rows for the same USDA food — what the pre-fix bug produced
        // every time the same search result was logged on different days.
        let day = Date()
        var dupes: [FoodItem] = []
        for i in 0..<3 {
            let item = FoodItem(name: "Chicken breast", source: "usda", fdcId: "12345",
                                 servingSize: 100, servingUnit: "g",
                                 calories: 165, protein: 31, carbs: 0, fat: 3.6)
            item.createdAt = day.addingTimeInterval(Double(i) * 60)
            context.insert(item)
            dupes.append(item)
        }
        dupes[1].isSaved = true // a later duplicate got favorited; the survivor must inherit it

        let entry1 = DiaryEntry(date: day, meal: "lunch", food: dupes[0], numberOfServings: 1)
        let entry2 = DiaryEntry(date: day, meal: "dinner", food: dupes[2], numberOfServings: 2)
        context.insert(entry1)
        context.insert(entry2)

        // A distinct food (different fdcId) must be left completely alone.
        let other = FoodItem(name: "Rice", source: "usda", fdcId: "999",
                              servingSize: 100, servingUnit: "g",
                              calories: 130, protein: 2.7, carbs: 28, fat: 0.3)
        context.insert(other)

        let totalCaloriesBefore = entry1.calories + entry2.calories

        UserDefaults.standard.removeObject(forKey: "foodDedupeMigrationV1")
        MigrationService.dedupeFoodItems(in: context)

        let allFoods = try context.fetch(FetchDescriptor<FoodItem>())
        let chickenRows = allFoods.filter { $0.fdcId == "12345" }
        XCTAssertEqual(chickenRows.count, 1, "3 duplicate rows must merge into 1")
        XCTAssertEqual(allFoods.count, 2, "one chicken survivor + the untouched rice row")

        let survivor = try XCTUnwrap(chickenRows.first)
        XCTAssertEqual(survivor.persistentModelID, dupes[0].persistentModelID, "keeps the oldest row")
        XCTAssertTrue(survivor.isSaved, "isSaved from a merged duplicate must carry over")

        XCTAssertEqual(entry1.food?.persistentModelID, survivor.persistentModelID)
        XCTAssertEqual(entry2.food?.persistentModelID, survivor.persistentModelID)
        XCTAssertEqual(entry1.calories + entry2.calories, totalCaloriesBefore, accuracy: 0.001,
                       "repointing must not change historical diary totals")

        // Idempotent: running again with the flag now set must be a no-op.
        MigrationService.dedupeFoodItems(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FoodItem>()).count, 2)

        UserDefaults.standard.removeObject(forKey: "foodDedupeMigrationV1")
    }
}
