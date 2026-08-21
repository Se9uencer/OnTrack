import Foundation
import SwiftData

// CloudKit rules: every attribute defaulted, every relationship optional, no .unique.

@Model
final class BodyWeightEntry {
    var date: Date = Date()
    var weightKg: Double = 0
    var source: String = "manual" // "manual" | "healthKit"
    var healthKitUUID: String? = nil
    var photoFilename: String? = nil // optional progress photo; blob lives in ImageStore, device-local

    init(date: Date = Date(), weightKg: Double, source: String = "manual", healthKitUUID: String? = nil, photoFilename: String? = nil) {
        self.date = date
        self.weightKg = weightKg
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.photoFilename = photoFilename
    }
}

@Model
final class CustomExercise {
    var id: String = UUID().uuidString
    var name: String = ""
    var primaryMuscle: String = ""
    var equipment: String = ""

    init(name: String, primaryMuscle: String, equipment: String) {
        self.id = "custom_" + UUID().uuidString
        self.name = name
        self.primaryMuscle = primaryMuscle
        self.equipment = equipment
    }
}

@Model
final class WorkoutTemplate {
    var name: String = ""
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var exercises: [TemplateExercise]? = []

    init(name: String) { self.name = name }

    var orderedExercises: [TemplateExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }
}

@Model
final class TemplateExercise {
    var exerciseID: String = ""
    var exerciseName: String = "" // snapshot so UI doesn't need a lookup
    var targetSets: Int = 3
    var order: Int = 0

    init(exerciseID: String, exerciseName: String, targetSets: Int, order: Int) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.targetSets = targetSets
        self.order = order
    }
}

@Model
final class WorkoutSession {
    var date: Date = Date()
    var templateName: String? = nil
    var isPlanned: Bool = false // scheduled for a future day, not yet started
    var kind: String = "workout" // "workout" | "rest" | "activity"
    @Relationship(deleteRule: .cascade) var sets: [LoggedSet]? = []

    init(date: Date = Date(), templateName: String? = nil, isPlanned: Bool = false, kind: String = "workout") {
        self.date = date
        self.templateName = templateName
        self.isPlanned = isPlanned
        self.kind = kind
    }

    var orderedSets: [LoggedSet] {
        (sets ?? []).sorted { $0.order < $1.order }
    }
}

@Model
final class LoggedSet {
    var exerciseID: String = ""
    var exerciseName: String = ""
    var weightKg: Double = 0
    var reps: Int = 0
    var order: Int = 0
    var date: Date = Date()

    init(exerciseID: String, exerciseName: String, weightKg: Double, reps: Int, order: Int, date: Date = Date()) {
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.weightKg = weightKg
        self.reps = reps
        self.order = order
        self.date = date
    }
}

@Model
final class FoodItem {
    var name: String = ""
    var brand: String? = nil
    var source: String = "manual" // "openFoodFacts" | "usda" | "manual"
    var barcode: String? = nil
    var servingSize: Double = 100
    var servingUnit: String = "g"
    // Macros are PER SERVING.
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var isSaved: Bool = false
    var createdAt: Date = Date()
    var imageFilename: String? = nil // photo meals: file in Documents/FoodImages (see ImageStore)

    init(name: String, brand: String? = nil, source: String, barcode: String? = nil,
         servingSize: Double, servingUnit: String,
         calories: Double, protein: Double, carbs: Double, fat: Double,
         imageFilename: String? = nil) {
        self.name = name
        self.brand = brand
        self.source = source
        self.barcode = barcode
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.imageFilename = imageFilename
    }
}

@Model
final class DiaryEntry {
    var date: Date = Date()
    var meal: String = "breakfast" // breakfast | lunch | dinner | snack
    var food: FoodItem? = nil
    var numberOfServings: Double = 1

    init(date: Date = Date(), meal: String, food: FoodItem, numberOfServings: Double = 1) {
        self.date = date
        self.meal = meal
        self.food = food
        self.numberOfServings = numberOfServings
    }

    var calories: Double { (food?.calories ?? 0) * numberOfServings }
    var protein: Double { (food?.protein ?? 0) * numberOfServings }
    var carbs: Double { (food?.carbs ?? 0) * numberOfServings }
    var fat: Double { (food?.fat ?? 0) * numberOfServings }
}

@Model
final class FaithLogEntry {
    var day: Date = Date()
    var itemKey: String = "" // "fard.fajr", "sunnah.dhuhr.before", "extra.witr"
    var status: String = "" // fard: "onTime" | "late" | "missed"; sunnah/extra: "done"

    init(day: Date, itemKey: String, status: String) {
        self.day = day
        self.itemKey = itemKey
        self.status = status
    }
}

@Model
final class UserProfile {
    var age: Int = 25
    var heightCm: Double = 175
    var sex: String = "male" // male | female
    var activityLevel: String = "moderate" // sedentary | light | moderate | active | veryActive
    var weeklyRateLbs: Double = 0 // -1, -0.5 (cut), 0 (maintain), +0.5, +1 (bulk) lb/week
    var calorieOverride: Double? = nil
    var proteinOverride: Double? = nil
    var carbsOverride: Double? = nil
    var fatOverride: Double? = nil

    init() {}
}
