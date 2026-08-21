import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var entries: [BodyWeightEntry]
    @AppStorage("useMetric") private var useMetric = false
    @AppStorage("weighInReminderEnabled") private var reminderEnabled = true
    @AppStorage("weighInReminderHour") private var reminderHour = 8
    @AppStorage("weighInReminderMinute") private var reminderMinute = 0
    @State private var showingLog = false
    @State private var showGallery = false
    @State private var galleryStart: BodyWeightEntry?

    var body: some View {
        NavigationStack {
            List {
                if entries.count >= 2 {
                    Section("Trend") {
                        chart
                            .frame(height: 220)
                            .listRowInsets(EdgeInsets(top: 12, leading: 8, bottom: 12, trailing: 16))
                    }
                }
                Section("History") {
                    if entries.isEmpty {
                        Text("No weigh-ins yet. Tap + to log your first.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        historyRow(entry)
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
            .navigationTitle("Weight")
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { galleryStart = nil; showGallery = true } label: {
                        Image(systemName: "photo.stack")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLog = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(isPresented: $showGallery) {
                ProgressGalleryView(startAt: galleryStart)
            }
            .sheet(isPresented: $showingLog) {
                LogWeightSheet { refreshReminder() }
            }
            .task {
                await HealthKitService.shared.importExternalWeights(context: context)
                refreshReminder()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await HealthKitService.shared.importExternalWeights(context: context) }
                    refreshReminder()
                }
            }
        }
    }

    private func historyRow(_ entry: BodyWeightEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Units.kgToDisplay(entry.weightKg, metric: useMetric), format: .number.precision(.fractionLength(1))) \(Units.weightLabel(metric: useMetric))")
                .bold()
            if entry.source == "healthKit" {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .font(.caption)
            }
            if let name = entry.photoFilename, let ui = ImageStore.load(name) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture { galleryStart = entry; showGallery = true }
            }
        }
    }

    private func deleteEntries(_ indexSet: IndexSet) {
        for i in indexSet {
            if let name = entries[i].photoFilename { ImageStore.delete(name) }
            context.delete(entries[i])
        }
    }

    private var loggedToday: Bool {
        entries.contains { Calendar.current.isDateInToday($0.date) }
    }

    private func refreshReminder() {
        NotificationService.shared.rescheduleWeighInReminder(
            enabled: reminderEnabled, alreadyLoggedToday: loggedToday,
            hour: reminderHour, minute: reminderMinute)
    }

    private var chart: some View {
        let recent = entries.prefix(90).reversed()
        return Chart(recent) { entry in
            LineMark(
                x: .value("Date", entry.date),
                y: .value("Weight", Units.kgToDisplay(entry.weightKg, metric: useMetric)))
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", entry.date),
                y: .value("Weight", Units.kgToDisplay(entry.weightKg, metric: useMetric)))
            .symbolSize(24)
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

// MARK: - Log weight (with optional progress photo)

struct LogWeightSheet: View {
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("useMetric") private var useMetric = false
    @State private var weightText = ""
    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Weigh-in") {
                    HStack {
                        TextField("Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text(Units.weightLabel(metric: useMetric)).foregroundStyle(.secondary)
                    }
                }
                Section {
                    photoArea
                } header: {
                    Text("Progress photo (optional)")
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        image = ui
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView { image = $0 }
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .listRowInsets(EdgeInsets())
            Button(role: .destructive) { self.image = nil; photoItem = nil } label: {
                Label("Remove photo", systemImage: "trash")
            }
        } else {
            Button { showingCamera = true } label: {
                Label("Take photo", systemImage: "camera.fill")
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.fill")
            }
        }
    }

    private var isValid: Bool {
        (Double(weightText) ?? 0) > 0
    }

    private func save() {
        guard let value = Double(weightText), value > 0 else { return }
        let kg = Units.displayToKg(value, metric: useMetric)
        let filename = image.flatMap { downscaledJPEG($0) }.flatMap { ImageStore.save($0) }
        context.insert(BodyWeightEntry(weightKg: kg, photoFilename: filename))
        Task { try? await HealthKitService.shared.saveWeight(kg, date: Date()) }
        onSaved()
        dismiss()
    }

    /// Max 1080px long edge, JPEG 0.7 — progress photos want more detail than meal shots.
    private func downscaledJPEG(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 1080
        let scale = min(1, maxDim / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.7)
    }
}
