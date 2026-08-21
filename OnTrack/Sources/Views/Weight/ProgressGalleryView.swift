import SwiftUI
import SwiftData

/// Full-screen viewer for progress photos attached to weigh-ins.
/// Two modes: single (swipe through days) and compare (two days side by side).
struct ProgressGalleryView: View {
    /// Entry to open on first; nil starts at the most recent photo.
    let startAt: BodyWeightEntry?

    @Query(sort: \BodyWeightEntry.date) private var allEntries: [BodyWeightEntry]
    @AppStorage("useMetric") private var useMetric = false
    @State private var mode: Mode = .single
    @State private var index = 0
    @State private var leftIndex = 0
    @State private var rightIndex = 0
    @State private var activeSide: Side = .right
    @State private var started = false

    enum Mode { case single, compare }
    enum Side { case left, right }

    // Oldest → newest, so compare reads naturally as before → after.
    private var photos: [BodyWeightEntry] { allEntries.filter { $0.photoFilename != nil } }

    var body: some View {
        Group {
            if photos.isEmpty {
                emptyState
            } else {
                VStack(spacing: 16) {
                    modePicker
                    if mode == .single { singleMode } else { compareMode }
                    filmstrip
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Progress Gallery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .single, let img = image(at: index) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview(caption(photos[index]), image: Image(uiImage: img))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            index = startAt.flatMap { photos.firstIndex(of: $0) } ?? (photos.count - 1)
            leftIndex = 0
            rightIndex = photos.count - 1
        }
    }

    // MARK: Mode toggle (single square / split)

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Image(systemName: "square").tag(Mode.single)
            Image(systemName: "rectangle.split.2x1").tag(Mode.compare)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    // MARK: Single

    private var singleMode: some View {
        VStack(spacing: 10) {
            TabView(selection: $index) {
                ForEach(photos.indices, id: \.self) { i in
                    GalleryImage(filename: photos[i].photoFilename)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal, 16)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxHeight: .infinity)
            caption(for: photos[safe: index])
        }
    }

    // MARK: Compare

    private var compareMode: some View {
        HStack(spacing: 10) {
            comparePanel(i: leftIndex, side: .left)
            comparePanel(i: rightIndex, side: .right)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private func comparePanel(i: Int, side: Side) -> some View {
        VStack(spacing: 8) {
            GalleryImage(filename: photos[safe: i]?.photoFilename)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(activeSide == side ? Color.accentColor : .clear, lineWidth: 3))
            caption(for: photos[safe: i])
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { activeSide = side }
    }

    // MARK: Filmstrip — tap to set current (single) or active side (compare)

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(photos.indices, id: \.self) { i in
                    Button { select(i) } label: {
                        GalleryImage(filename: photos[i].photoFilename)
                            .frame(width: 54, height: 54)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isSelected(i) ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 62)
    }

    private func select(_ i: Int) {
        withAnimation {
            switch mode {
            case .single: index = i
            case .compare: if activeSide == .left { leftIndex = i } else { rightIndex = i }
            }
        }
    }

    private func isSelected(_ i: Int) -> Bool {
        switch mode {
        case .single: return i == index
        case .compare: return activeSide == .left ? i == leftIndex : i == rightIndex
        }
    }

    // MARK: Helpers

    private func image(at i: Int) -> UIImage? {
        guard let name = photos[safe: i]?.photoFilename else { return nil }
        return ImageStore.load(name)
    }

    @ViewBuilder
    private func caption(for entry: BodyWeightEntry?) -> some View {
        if let entry {
            VStack(spacing: 2) {
                Text("\(Units.kgToDisplay(entry.weightKg, metric: useMetric), format: .number.precision(.fractionLength(1))) \(Units.weightLabel(metric: useMetric))")
                    .font(.headline)
                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
        }
    }

    private func caption(_ entry: BodyWeightEntry) -> String {
        let w = String(format: "%.1f", Units.kgToDisplay(entry.weightKg, metric: useMetric))
        return "\(w) \(Units.weightLabel(metric: useMetric)) · \(entry.date.formatted(date: .abbreviated, time: .omitted))"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No progress photos yet")
                .font(.title3.bold())
            Text("Add a photo when you log a weigh-in and it'll show up here to scroll through and compare.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

/// Loads a progress photo from disk (device-local; falls back to a placeholder).
/// Color.clear takes the size the parent offers; the overlaid image fills and
/// crops to it — so it never overflows its column the way a bare scaledToFill does.
private struct GalleryImage: View {
    let filename: String?

    var body: some View {
        // ponytail: loads full-res from disk per render; fine for the handful of
        // weigh-in photos. Add a thumbnail cache if strips ever get long.
        Color.clear
            .overlay {
                if let filename, let ui = ImageStore.load(filename) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.secondarySystemBackground)
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipped()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
