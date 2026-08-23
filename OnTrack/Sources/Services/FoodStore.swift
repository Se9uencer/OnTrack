import Foundation
import SwiftData

/// Single insertion point for catalog foods (search results, barcode lookups, bundled
/// database rows) so re-logging the same food doesn't spawn a duplicate FoodItem every time.
///
/// Manual entries and photo-meal estimates deliberately do NOT go through here — they have
/// no stable external identity, and folding them by name risks silently reusing a different
/// meal's macros/photo. Those stay one-row-per-log, which is correct for a journal entry.
enum FoodStore {
    static func findOrCreate(_ result: FoodSearchResult, in context: ModelContext) -> FoodItem {
        let candidate = result.toFoodItem()
        let key = candidate.dedupeKey
        // ponytail: fetch-all + linear scan; fine at a personal food log's scale (dozens-hundreds
        // of rows). Add a predicate/index if this ever shows up in a profile.
        if let existing = try? context.fetch(FetchDescriptor<FoodItem>()).first(where: { $0.dedupeKey == key }) {
            return existing
        }
        context.insert(candidate)
        return candidate
    }
}
