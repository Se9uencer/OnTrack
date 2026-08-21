import Foundation
import HealthKit
import SwiftData

final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    private let bodyMass = HKQuantityType(.bodyMass)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: [bodyMass], read: [bodyMass])
    }

    func saveWeight(_ kg: Double, date: Date) async throws {
        let sample = HKQuantitySample(
            type: bodyMass,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date)
        try await store.save(sample)
    }

    /// Pull weight samples logged by OTHER apps (scale, Health app) into SwiftData.
    /// Dedup: skip our own writes (source == this app) and samples already imported (healthKitUUID).
    @MainActor
    func importExternalWeights(context: ModelContext) async {
        guard isAvailable else { return }
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: bodyMass, predicate: nil, limit: 200,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, results, _ in
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        let ownBundleID = Bundle.main.bundleIdentifier ?? ""
        let existing = (try? context.fetch(FetchDescriptor<BodyWeightEntry>())) ?? []
        let knownUUIDs = Set(existing.compactMap(\.healthKitUUID))
        for sample in samples {
            let uuid = sample.uuid.uuidString
            guard sample.sourceRevision.source.bundleIdentifier != ownBundleID,
                  !knownUUIDs.contains(uuid) else { continue }
            let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
            context.insert(BodyWeightEntry(date: sample.startDate, weightKg: kg,
                                           source: "healthKit", healthKitUUID: uuid))
        }
    }

}
