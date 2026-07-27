import SwiftUI
import PhotosUI

struct PhotoCaptureFlowView: View {
    let onFinished: () -> Void

    @State private var capturedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isAnalyzing = false
    @State private var analysisResult: NutritionAnalysisResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let capturedImage {
                    Image(uiImage: capturedImage)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding()
                } else {
                    ContentUnavailableView(
                        "Capture your meal",
                        systemImage: "camera.fill",
                        description: Text("Take a photo or choose one from your library.")
                    )
                }

                if isAnalyzing {
                    ProgressView("Analyzing with AI…").padding()
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label(capturedImage == nil ? "Open Camera" : "Retake Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    PhotosPicker(selection: $photoPickerItem, matching: .images) {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if capturedImage != nil {
                        Button {
                            analyze()
                        } label: {
                            Label("Analyze", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.themeOlive)
                        .disabled(isAnalyzing)
                    }
                }
                .padding()
            }
            .themedScreenBackground()
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: photoPickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
                        capturedImage = uiImage
                    }
                }
            }
            .fullScreenCover(item: $analysisResult) { result in
                NutritionConfirmView(result: result, image: capturedImage, source: .photo, onFinished: onFinished)
            }
        }
    }

    private func analyze() {
        guard let capturedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let result = try await AINutritionService.shared.analyzePhoto(capturedImage, userNote: nil)
                await MainActor.run {
                    isAnalyzing = false
                    analysisResult = result
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

extension NutritionAnalysisResult: Identifiable {
    var id: String { name + servingDescription }
}
