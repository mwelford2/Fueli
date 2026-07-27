import SwiftUI

struct DescribeMealFlowView: View {
    let onFinished: () -> Void

    @State private var description = ""
    @State private var isAnalyzing = false
    @State private var errorMessage: String?
    @State private var analysisResult: NutritionAnalysisResult?
    @State private var needsSetup = false
    @State private var showProviderSettings = false
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Describe what you ate, including portion size for the best estimate.")
                    .font(.themeSubheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                TextEditor(text: $description)
                    .focused($isFocused)
                    .frame(height: 140)
                    .padding(8)
                    .background(Color.themeCard)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        if description.isEmpty {
                            Text("e.g. Grilled chicken breast with a cup of rice and steamed broccoli")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 30)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }

                if isAnalyzing {
                    ProgressView("Analyzing with AI…")
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if needsSetup {
                    AISetupPromptCard { showProviderSettings = true }
                }

                Spacer()

                Button {
                    isFocused = false
                    analyze()
                } label: {
                    Label("Analyze", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || isAnalyzing)
                .padding()
            }
            .padding(.top)
            .themedScreenBackground()
            .navigationTitle("Describe Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinished() }
                }
            }
            .fullScreenCover(item: $analysisResult) { result in
                NutritionConfirmView(result: result, source: .textDescription, onFinished: onFinished)
            }
            .sheet(isPresented: $showProviderSettings) {
                NavigationStack {
                    AIProviderSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showProviderSettings = false }
                            }
                        }
                }
            }
            .onChange(of: showProviderSettings) { _, isPresented in
                if !isPresented && AIProviderConfig.load().isConfigured {
                    withAnimation { needsSetup = false }
                }
            }
        }
    }

    private func analyze() {
        guard AIProviderConfig.load().isConfigured else {
            withAnimation { needsSetup = true }
            return
        }
        isAnalyzing = true
        errorMessage = nil
        Task {
            do {
                let result = try await AINutritionService.shared.analyzeDescription(description)
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

/// Themed inline prompt shown when an AI feature is used before a provider is configured.
struct AISetupPromptCard: View {
    let onSetUp: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text("AI isn't set up yet")
                .font(.headline)
            Text("Add your provider's API key to analyze meals with AI.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onSetUp) {
                Label("Set Up AI Provider", systemImage: "gearshape.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }
}
#Preview {
    DescribeMealFlowView(onFinished: {})
        .modelContainer(PreviewData.emptyContainer())
}

#Preview("Setup prompt") {
    ZStack {
        Color.themeBackground.ignoresSafeArea()
        AISetupPromptCard {}
    }
}

