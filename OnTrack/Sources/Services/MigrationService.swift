import Foundation
import SwiftData

/// One-time data fixups that can't be expressed as a SwiftData schema migration.
enum MigrationService {
    /// Merges duplicate FoodItem rows created by the pre-1.2.0 bug where every catalog
    /// search/barcode tap inserted a new row instead of reusing an existing one.
    ///
    /// Only merges rows with a stable external identity (fdcId or barcode) — those are
    /// genuinely the same food. Manual/photo entries have no such identity and sharing a
    /// name doesn't mean sharing macros, so they're left untouched rather than risk folding
    /// two different logged meals into one.
    static func dedupeFoodItems(in context: ModelContext) {
        let flagKey = "foodDedupeMigrationV1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        guard let allFoods = try? context.fetch(FetchDescriptor<FoodItem>()) else { return }
        let candidates = allFoods.filter { $0.fdcId != nil || $0.barcode != nil }
        let groups = Dictionary(grouping: candidates, by: \.dedupeKey)

        guard let allEntries = try? context.fetch(FetchDescriptor<DiaryEntry>()) else { return }

        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { $0.createdAt < $1.createdAt }
            guard let survivor = sorted.first else { continue }
            let duplicates = Array(sorted.dropFirst())
            let dupSet = Set(duplicates.map(\.persistentModelID))

            if duplicates.contains(where: { $0.isSaved }) {
                survivor.isSaved = true
            }
            for entry in allEntries where entry.food.map({ dupSet.contains($0.persistentModelID) }) == true {
                entry.food = survivor
            }
            for dup in duplicates {
                context.delete(dup)
            }
        }

        UserDefaults.standard.set(true, forKey: flagKey)
        try? context.save()
    }
}
