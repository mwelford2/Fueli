import SwiftUI

/// Shared AI provider setup form used in both Settings and Onboarding.
struct AISetupFormView: View {
    @State private var preset: AIProviderPreset
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var isTesting = false
    @State private var testResult: TestResult?

    private enum TestResult: Identifiable {
        case success, failure(String)
        var id: Int { switch self { case .success: return 0; case .failure: return 1 } }
    }

    init() {
        let config = AIProviderConfig.load()
        _preset = State(initialValue: config.preset)
        _baseURL = State(initialValue: config.baseURL)
        _model = State(initialValue: config.model)
        _apiKey = State(initialValue: config.apiKey)
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $preset) {
                    ForEach(AIProviderPreset.allCases) { p in
                        Text(p.label).tag(p)
                    }
                }
                .onChange(of: preset) { _, newValue in
                    baseURL = newValue.defaultBaseURL
                    model = newValue.defaultModel
                }
            }

            Section("Connection") {
                if preset == .custom {
                    HStack {
                        TextField("Base URL", text: $baseURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !baseURL.isEmpty {
                            Button { baseURL = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !model.isEmpty {
                        Button { model = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    SecureField("API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !apiKey.isEmpty {
                        Button { apiKey = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button {
                    save()
                    testConnection()
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Text("Save & Test Connection")
                    }
                }
                .disabled(apiKey.isEmpty || model.isEmpty || (preset == .custom && baseURL.isEmpty) || isTesting)
            } footer: {
                Text("Your API key is stored securely in the iOS Keychain and is only sent to the configured provider.")
            }
        }
        .themedScreenBackground()
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { save() }
        .alert(item: $testResult) { result in
            switch result {
            case .success:
                return Alert(title: Text("Connected"), message: Text("Successfully reached the AI provider."), dismissButton: .default(Text("OK")))
            case .failure(let message):
                return Alert(title: Text("Connection Failed"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func save() {
        let config = AIProviderConfig(preset: preset, baseURL: baseURL, model: model)
        config.save()
        config.apiKey = apiKey
    }

    private func testConnection() {
        isTesting = true
        Task {
            do {
                try await AINutritionService.shared.testConnection()
                await MainActor.run {
                    isTesting = false
                    testResult = .success
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }
}

struct AIProviderSettingsView: View {
    var body: some View {
        AISetupFormView()
    }
}
