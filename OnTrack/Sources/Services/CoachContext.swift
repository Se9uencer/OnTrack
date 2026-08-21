import Foundation
import SwiftData

enum CoachContext {
    /// Compact 7-day summary of weight, diet, and workouts for AI prompts.
    /// Returns nil if there's too little data to give meaningful advice.
    @MainActor
    static func build(context: ModelContext) async -> String? {
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: Date()))!

        // Only app-logged data ever leaves the device for the AI. HealthKit-sourced
        // weights (scale/Health app imports) and activity are excluded — Apple's HealthKit
        // terms forbid sharing HealthKit data with third parties like the AI provider.
        let weights = ((try? context.fetch(FetchDescriptor<BodyWeightEntry>(
            predicate: #Predicate { $0.date >= weekAgo && $0.source != "healthKit" },
            sortBy: [SortDescriptor(\.date)]))) ?? [])
        let diary = ((try? context.fetch(FetchDescriptor<DiaryEntry>(
            predicate: #Predicate { $0.date >= weekAgo },
            sortBy: [SortDescriptor(\.date)]))) ?? [])
        let now = Date()
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= weekAgo && $0.date <= now && !$0.isPlanned && $0.kind == "workout" },
            sortBy: [SortDescriptor(\.date)]))) ?? [])

        // Sparse-data guard: don't let the model hallucinate advice from nothing.
        guard weights.count + diary.count + sessions.count >= 3 else { return nil }

        var lines: [String] = []

        if let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first {
            let weightKg = weights.last?.weightKg ?? 70
            let target = Calculations.calorieTarget(profile: profile, weightKg: weightKg)
            let macros = Calculations.macroTargets(profile: profile, weightKg: weightKg)
            lines.append("Profile: \(profile.age)yo \(profile.sex), \(Int(profile.heightCm))cm, goal: \(Calculations.goalDescription(profile.weeklyRateLbs)), activity: \(profile.activityLevel)")
            lines.append("Daily targets: \(Int(target)) kcal, \(Int(macros.protein))g protein, \(Int(macros.carbs))g carbs, \(Int(macros.fat))g fat")
        }

        if !weights.isEmpty {
            let entries = weights.map { "\(shortDate($0.date)): \(String(format: "%.1f", $0.weightKg))kg" }
            lines.append("Body weight (7d): " + entries.joined(separator: ", "))
        }

        if !diary.isEmpty {
            var byDay: [String: (cal: Double, p: Double, c: Double, f: Double)] = [:]
            for e in diary {
                let key = shortDate(e.date)
                var day = byDay[key] ?? (0, 0, 0, 0)
                day.cal += e.calories; day.p += e.protein; day.c += e.carbs; day.f += e.fat
                byDay[key] = day
            }
            let days = byDay.sorted { $0.key < $1.key }
                .map { "\($0.key): \(Int($0.value.cal))kcal P\(Int($0.value.p)) C\(Int($0.value.c)) F\(Int($0.value.f))" }
            lines.append("Diet (7d): " + days.joined(separator: " | "))
        }

        if !sessions.isEmpty {
            let summaries = sessions.map { s in
                let sets = s.orderedSets
                let exercises = Dictionary(grouping: sets, by: \.exerciseName)
                    .map { name, sets in
                        let top = sets.max { $0.weightKg < $1.weightKg }!
                        return "\(name) \(sets.count)x, top \(String(format: "%.0f", top.weightKg))kg x\(top.reps)"
                    }
                return "\(shortDate(s.date)) [\(s.templateName ?? "freeform")]: \(exercises.joined(separator: "; "))"
            }
            lines.append("Workouts (7d): " + summaries.joined(separator: " || "))
        }

        return lines.joined(separator: "\n")
    }

    static let systemPrompt = """
    You are a knowledgeable, encouraging fitness coach inside a personal fitness tracking app. \
    The user's recent logged data is provided below. Give specific, actionable advice grounded in \
    their actual numbers, framed by their goal (target rate of weight change). Be concise — a few \
    short paragraphs or a tight list, no fluff. Do not invent data they didn't log.

    Stay strictly within fitness, nutrition, training, and everyday wellness. If asked about anything \
    outside that scope, briefly decline and steer back to their health goals. You are not a doctor: \
    never diagnose, prescribe, or give medical, mental-health, or medication dosing advice — point the \
    user to a qualified professional instead. Never encourage unsafe practices such as extreme calorie \
    restriction, very rapid weight loss, disordered-eating behaviors, or unsafe supplement or drug use; \
    always favor safe, sustainable, evidence-based guidance. If a message suggests self-harm or an \
    eating disorder, respond with care and point the user toward professional support.
    """

    private static func shortDate(_ d: Date) -> String {
        d.formatted(.dateTime.month(.abbreviated).day())
    }
}
