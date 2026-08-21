import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let center = UNUserNotificationCenter.current()

    func setupDelegate() {
        center.delegate = self
        scheduleWeeklyRecap()
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Daily 9pm calorie check-in
    // iOS can't compute notification content at fire time, so we re-schedule
    // with fresh content every time the diary changes.
    func rescheduleDailyCheckIn(caloriesLogged: Double, target: Double) {
        center.removePendingNotificationRequests(withIdentifiers: ["dailyCheckIn"])
        let content = UNMutableNotificationContent()
        content.title = "Daily check-in"
        let remaining = target - caloriesLogged
        if caloriesLogged == 0 {
            content.body = "You haven't logged any food today. Don't forget to track!"
        } else if remaining > 100 {
            content.body = "You're at \(Int(caloriesLogged)) kcal — \(Int(remaining)) left to hit your \(Int(target)) target."
        } else if remaining >= -100 {
            content.body = "Nice — \(Int(caloriesLogged)) kcal logged, right on your \(Int(target)) target."
        } else {
            content.body = "You're at \(Int(caloriesLogged)) kcal, \(Int(-remaining)) over your \(Int(target)) target."
        }
        content.sound = .default
        var comps = DateComponents()
        comps.hour = 21
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "dailyCheckIn", content: content, trigger: trigger))
    }

    // MARK: Weekly recap (Sunday 6pm) — static body, AI summary generated on tap
    func scheduleWeeklyRecap() {
        let content = UNMutableNotificationContent()
        content.title = "Weekly recap"
        content.body = "Your weekly breakdown of weight, workouts, and diet is ready."
        content.sound = .default
        content.userInfo = ["deepLink": "coach"]
        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = 18
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "weeklyRecap", content: content, trigger: trigger))
    }

    // MARK: Daily weigh-in reminder
    // One-shot, rescheduled each time: suppressed for today once you've logged,
    // then automatically resumes tomorrow at the chosen time.
    func rescheduleWeighInReminder(enabled: Bool, alreadyLoggedToday: Bool, hour: Int, minute: Int) {
        center.removePendingNotificationRequests(withIdentifiers: ["weighInReminder"])
        guard enabled else { return }

        let cal = Calendar.current
        let now = Date()
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        guard var fireDate = cal.date(from: comps) else { return }
        if fireDate <= now || alreadyLoggedToday {
            fireDate = cal.date(byAdding: .day, value: 1, to: fireDate)!
        }

        let content = UNMutableNotificationContent()
        content.title = "Weigh-in reminder"
        content.body = "Time to log today's weight."
        content.sound = .default
        let triggerComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        center.add(UNNotificationRequest(identifier: "weighInReminder", content: content, trigger: trigger))
    }

    // MARK: Rest timer
    func scheduleRestDone(seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        center.add(UNNotificationRequest(identifier: "restTimer", content: content, trigger: trigger))
    }

    func cancelRestTimer() {
        center.removePendingNotificationRequests(withIdentifiers: ["restTimer"])
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["deepLink"] as? String == "coach" {
            await MainActor.run {
                TabRouter.shared.selected = .today
                TabRouter.shared.presentCoach = true
                UserDefaults.standard.set(true, forKey: "pendingWeeklyRecap")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
