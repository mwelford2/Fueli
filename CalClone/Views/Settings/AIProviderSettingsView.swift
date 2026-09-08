import SwiftUI

/// Shared AI provider setup form used in both Settings and Onboarding.
struct AISetupFormView: View {
    @State private var preset: AIProviderPreset
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey: String
    @State private var assumptionLevel: AssumptionLevel
    @State private var isTesting = false
    @State private var testResult: TestResult?

    @State private var discoveredModels: [AINutritionService.DiscoveredModel] = []
    @State private var isLoadingModels = false
    @State private var modelLoadError: String?

    private enum TestResult: Identifiable {
        case success, failure(String)
        var id: Int { switch self { case .success: return 0; case .failure: return 1 } }
    }

    private var canLoadModels: Bool {
        !apiKey.isEmpty && (preset != .custom || !baseURL.isEmpty)
    }

    private var effectiveBaseURL: String {
        preset == .custom ? baseURL : preset.defaultBaseURL
    }

    /// The model entry (if any) for the currently-selected id from a loaded list.
    private var selectedDiscoveredModel: AINutritionService.DiscoveredModel? {
        discoveredModels.first(where: { $0.id == model })
    }

    /// Whether models have been loaded at all this session.
    private var hasLoadedModels: Bool { !discoveredModels.isEmpty }

    /// Fueli needs a model that positively supports BOTH text and image input. We
    /// only allow completing setup once we can confirm that — an unknown-capability
    /// model does not pass (we don't assume).
    private var selectedModelSupportsVision: Bool {
        // Before the user has loaded any models, don't block the button on this — the
        // other disabled conditions (empty key/url) already gate it, and the footer
        // tells them to load models. Once a list is loaded, the selection must verify.
        guard hasLoadedModels else { return true }
        return selectedDiscoveredModel?.supportsTextAndImage == true
    }

    private var visionWarning: String? {
        guard hasLoadedModels else { return nil }
        guard let m = selectedDiscoveredModel else {
            return "“\(model)” isn’t in the loaded list. Pick a model from the list so Fueli can confirm it supports food photos."
        }
        switch m.capabilities {
        case .none:
            return "Couldn’t determine whether “\(m.id)” supports images — from the provider or models.dev. Pick a model with a confirmed Vision capability."
        case .some(let caps) where !caps.contains(.image):
            return "“\(m.id)” doesn’t support image input. Fueli needs a vision-capable model to analyze food photos."
        case .some(let caps) where !caps.contains(.text):
            return "“\(m.id)” doesn’t support text input, which Fueli needs."
        default:
            return nil
        }
    }

    init() {
        let config = AIProviderConfig.load()
        _preset = State(initialValue: config.preset)
        _baseURL = State(initialValue: config.baseURL)
        _model = State(initialValue: config.model)
        _apiKey = State(initialValue: config.apiKey)
        _assumptionLevel = State(initialValue: config.assumptionLevel)
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
                HStack {
                    TextField("Model name", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isLoadingModels {
                        ProgressView()
                    } else {
                        Button {
                            loadModels()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .disabled(!canLoadModels)
                    }
                }

                if !discoveredModels.isEmpty {
                    Picker("Available models", selection: $model) {
                        ForEach(discoveredModels) { m in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(m.id)
                                    if m.supportsTextAndImage {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                }
                                Text(m.capabilityLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(m.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                if let visionWarning {
                    Label(visionWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Model")
            } footer: {
                if let modelLoadError {
                    Text(modelLoadError).foregroundStyle(.red)
                } else if discoveredModels.isEmpty {
                    Text("Enter your key (and base URL for a custom endpoint), then tap ↻ to load the models this provider offers. Fueli needs a model that supports both text and image input.")
                } else {
                    Text("\(discoveredModels.count) models loaded. ✓ marks models confirmed to support text + images (from the provider or models.dev); ⚠︎ marks the rest. Capabilities are never guessed from the name.")
                }
            }

            Section {
                Picker("Meal analysis", selection: $assumptionLevel) {
                    ForEach(AssumptionLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .onChange(of: assumptionLevel) { _, _ in save() }
            } header: {
                Text("Follow-up questions")
            } footer: {
                Text(assumptionLevel.detail)
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
                .disabled(
                    apiKey.isEmpty
                    || model.isEmpty
                    || (preset == .custom && baseURL.isEmpty)
                    || isTesting
                    || !selectedModelSupportsVision
                )
            } footer: {
                if !selectedModelSupportsVision {
                    Text("Choose a model that supports image input before continuing.")
                        .foregroundStyle(.red)
                } else {
                    Text("Your API key is stored securely in the iOS Keychain and is only sent to the configured provider.")
                }
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
        let config = AIProviderConfig(preset: preset, baseURL: baseURL, model: model, assumptionLevel: assumptionLevel)
        config.save()
        config.apiKey = apiKey
    }

    private func loadModels() {
        guard canLoadModels else { return }
        isLoadingModels = true
        modelLoadError = nil
        let base = effectiveBaseURL
        let key = apiKey
        let p = preset
        Task {
            do {
                let models = try await AINutritionService.shared.fetchModels(baseURL: base, apiKey: key, preset: p)
                await MainActor.run {
                    isLoadingModels = false
                    discoveredModels = models
                    if models.isEmpty {
                        modelLoadError = "The provider returned no models."
                    } else if models.first(where: { $0.id == model })?.supportsTextAndImage != true {
                        // Current selection is missing / not vision-capable — jump to
                        // the first model we've confirmed handles text + images.
                        if let firstVision = models.first(where: { $0.supportsTextAndImage }) {
                            model = firstVision.id
                        } else if !models.contains(where: { $0.id == model }) {
                            model = models[0].id
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingModels = false
                    modelLoadError = error.localizedDescription
                }
            }
        }
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
