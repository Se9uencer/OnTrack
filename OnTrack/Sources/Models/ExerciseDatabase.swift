import Foundation

// Bundled free-exercise-db. Read-only, in-memory, deliberately NOT in SwiftData
// (seeding a CloudKit-synced store duplicates rows across devices).
struct BundledExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let equipment: String?
    let primaryMuscles: [String]
    let category: String
    let instructions: [String]

    var primaryMuscle: String { primaryMuscles.first ?? "" }
}

enum ExerciseDatabase {
    static let all: [BundledExercise] = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([BundledExercise].self, from: data)
        else { return [] }
        return list.sorted { $0.name < $1.name }
    }()

    private static let byID: [String: BundledExercise] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func find(_ id: String) -> BundledExercise? { byID[id] }

    static func search(_ query: String) -> [BundledExercise] {
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}
