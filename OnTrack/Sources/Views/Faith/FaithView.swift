import SwiftUI
import SwiftData

// MARK: - Static catalog

private struct SunnahItem: Identifiable {
    let id: String // full itemKey, e.g. "sunnah.dhuhr.before"
    let label: String // "2 before"
}

private struct FardPrayer: Identifiable {
    let id: String // "fajr", "dhuhr", ...
    let name: String
    let sunnah: [SunnahItem]

    var itemKey: String { "fard.\(id)" }
}

private struct ExtraItem: Identifiable {
    let id: String // full itemKey, e.g. "extra.witr"
    let name: String
}

private let fardCatalog: [FardPrayer] = [
    FardPrayer(id: "fajr", name: "Fajr", sunnah: [
        SunnahItem(id: "sunnah.fajr.before", label: "2 before"),
    ]),
    FardPrayer(id: "dhuhr", name: "Dhuhr", sunnah: [
        SunnahItem(id: "sunnah.dhuhr.before", label: "4 before"),
        SunnahItem(id: "sunnah.dhuhr.after", label: "2 after"),
    ]),
    FardPrayer(id: "asr", name: "Asr", sunnah: []),
    FardPrayer(id: "maghrib", name: "Maghrib", sunnah: [
        SunnahItem(id: "sunnah.maghrib.after", label: "2 after"),
    ]),
    FardPrayer(id: "isha", name: "Isha", sunnah: [
        SunnahItem(id: "sunnah.isha.after", label: "2 after"),
    ]),
]

private let extrasCatalog: [ExtraItem] = [
    ExtraItem(id: "extra.witr", name: "Witr"),
    ExtraItem(id: "extra.tahajjud", name: "Tahajjud"),
    ExtraItem(id: "extra.duha", name: "Duha"),
]

// MARK: - Entry point

struct FaithView: View {
    @AppStorage("faithTradition") private var faithTradition = ""

    var body: some View {
        if faithTradition.isEmpty {
            FaithPickerView()
        } else {
            FaithTrackerView()
        }
    }
}

// MARK: - One-time tradition picker

private struct FaithPickerView: View {
    @AppStorage("faithTradition") private var faithTradition = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Islam").font(.title2.bold())
                    Text("Track your five daily prayers, sunnah, and more")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .card()
                Text("More traditions are coming soon.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Start Tracking") { faithTradition = "islam" }
                    .buttonStyle(PillButtonStyle())
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Faith")
        }
    }
}

// MARK: - Tracker

private struct FaithTrackerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FaithLogEntry.day, order: .reverse) private var entries: [FaithLogEntry]
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateHeader
                    streakCard
                    fardCard
                    extrasCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Faith")
        }
    }

    // MARK: Day state

    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    private var isPastDay: Bool { selectedDay < Calendar.current.startOfDay(for: Date()) }

    private var dayEntries: [FaithLogEntry] {
        entries.filter { Calendar.current.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private func status(for key: String) -> String? {
        dayEntries.first { $0.itemKey == key }?.status
    }

    private func cycleFard(_ key: String) {
        let next: String?
        switch status(for: key) {
        case nil: next = "onTime"
        case "onTime": next = "late"
        case "late": next = "missed"
        default: next = nil
        }
        if let existing = dayEntries.first(where: { $0.itemKey == key }) {
            if let next { existing.status = next } else { context.delete(existing) }
        } else if let next {
            context.insert(FaithLogEntry(day: selectedDay, itemKey: key, status: next))
        }
    }

    private func toggleDone(_ key: String) {
        if let existing = dayEntries.first(where: { $0.itemKey == key }) {
            context.delete(existing)
        } else {
            context.insert(FaithLogEntry(day: selectedDay, itemKey: key, status: "done"))
        }
    }

    // MARK: Date header

    private var dateHeader: some View {
        HStack {
            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(isToday ? "Today" : selectedDay.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)
            Spacer()
            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(isToday)
        }
        .padding()
        .card()
    }

    // MARK: Streak + week strip

    private func dayComplete(_ day: Date) -> Bool {
        let items = entries.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        return fardCatalog.allSatisfy { prayer in
            let s = items.first { $0.itemKey == prayer.itemKey }?.status
            return s == "onTime" || s == "late"
        }
    }

    private var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        var count = 0
        if dayComplete(day) { count += 1 }
        day = cal.date(byAdding: .day, value: -1, to: day)!
        while dayComplete(day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    private func dotColor(day: Date, prayer: FardPrayer) -> Color {
        let items = entries.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
        switch items.first(where: { $0.itemKey == prayer.itemKey })?.status {
        case "onTime": return .green
        case "late": return .orange
        case "missed": return .red
        default: return day < Calendar.current.startOfDay(for: Date()) ? .red : .gray
        }
    }

    private var weekStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (0..<7).reversed().map { cal.date(byAdding: .day, value: -$0, to: today)! }
        return HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        ForEach(fardCatalog) { prayer in
                            Circle()
                                .fill(dotColor(day: day, prayer: prayer))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(.orange)
                Text("\(streak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("day streak").font(.subheadline).foregroundStyle(.secondary)
            }
            weekStrip
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Fard section

    private var fardCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(fardCatalog.enumerated()), id: \.element.id) { index, prayer in
                fardRow(prayer)
                ForEach(prayer.sunnah) { sunnahRow($0) }
                if index < fardCatalog.count - 1 {
                    Divider().padding(.vertical, 4)
                }
            }
        }
        .padding()
        .card()
    }

    private func fardRow(_ prayer: FardPrayer) -> some View {
        let current = status(for: prayer.itemKey)
        return Button { cycleFard(prayer.itemKey) } label: {
            HStack {
                Text(prayer.name).font(.subheadline.bold())
                Spacer()
                statusLabel(current)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(_ status: String?) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case "onTime": return ("On time", .green)
            case "late": return ("Late", .orange)
            case "missed": return ("Missed", .red)
            default: return isPastDay ? ("Missed", .red) : ("—", .gray)
            }
        }()
        return Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func sunnahRow(_ sunnah: SunnahItem) -> some View {
        let done = status(for: sunnah.id) == "done"
        return Button { toggleDone(sunnah.id) } label: {
            HStack {
                Text("Sunnah · \(sunnah.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
            }
            .padding(.leading, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Extras section

    private var extrasCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(extrasCatalog.enumerated()), id: \.element.id) { index, extra in
                extraRow(extra)
                if index < extrasCatalog.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .card()
    }

    private func extraRow(_ extra: ExtraItem) -> some View {
        let done = status(for: extra.id) == "done"
        return Button { toggleDone(extra.id) } label: {
            HStack {
                Text(extra.name).font(.subheadline)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? .green : .secondary)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
