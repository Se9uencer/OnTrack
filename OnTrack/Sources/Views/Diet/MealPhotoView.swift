import SwiftUI
import PhotosUI

struct MealPhotoView: View {
    /// Called with the AI-estimated food (already macro-filled, per whole meal).
    let onEstimated: (FoodItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("aiConsentGiven") private var aiConsentGiven = false
    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var descriptionText = ""
    @State private var analyzing = false
    @State private var errorText: String?
    @State private var showConsent = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    imageArea
                    descriptionField
                    Text("AI estimate — approximate, not nutritional advice. Adjust the values after adding.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                    analyze()
                } label: {
                    if analyzing {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Analyzing…")
                        }
                    } else {
                        Label("Analyze", systemImage: "sparkles")
                    }
                }
                .buttonStyle(PillButtonStyle())
                .disabled(image == nil || analyzing)
                .opacity(image == nil ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }
            .navigationTitle("Photo Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
                CameraCaptureView { captured in
                    image = captured
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showConsent) {
                AIConsentSheet { analyze() }
            }
            .sheet(isPresented: $showPaywall) {
                ProPaywallView { analyze() }
            }
        }
    }

    @ViewBuilder
    private var imageArea: some View {
        if let image {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                Button { self.image = nil } label: {
                    Label("Change", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(12)
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 90, height: 90)
                    .background(Color.accentColor.opacity(0.15), in: Circle())
                VStack(spacing: 6) {
                    Text("Snap your meal")
                        .font(.title3.bold())
                    Text("Get instant calorie and macro estimates from a photo.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button { showingCamera = true } label: {
                        pickerLabel("Camera", icon: "camera.fill")
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        pickerLabel("Library", icon: "photo.fill")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .card()
        }
    }

    private func pickerLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }

    private var descriptionField: some View {
        TextField("Describe it (optional) — e.g. chicken burrito, large",
                  text: $descriptionText, axis: .vertical)
            .lineLimit(1...3)
            .padding(14)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func analyze() {
        guard Pro.isActive else { showPaywall = true; return }
        guard aiConsentGiven else { showConsent = true; return }
        guard let image, let jpeg = downscaledJPEG(image) else { return }
        analyzing = true
        errorText = nil
        Task {
            do {
                let est = try await AIClient.estimateMeal(imageJPEG: jpeg, description: descriptionText)
                let item = FoodItem(name: est.name, source: "photo",
                                    servingSize: 1, servingUnit: "meal",
                                    calories: est.calories, protein: est.protein_g,
                                    carbs: est.carbs_g, fat: est.fat_g,
                                    imageFilename: ImageStore.save(jpeg))
                await MainActor.run {
                    analyzing = false
                    onEstimated(item)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    analyzing = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    /// Max 768px on the long edge, JPEG 0.6 — keeps the upload ~100-200 KB.
    private func downscaledJPEG(_ image: UIImage) -> Data? {
        let maxDim: CGFloat = 768
        let scale = min(1, maxDim / max(image.size.width, image.size.height))
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.6)
    }
}

/// Minimal camera wrapper — VisionKit's scanner is barcode-only, so photos use UIImagePickerController.
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
