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
    @State private var isLookingUpCapabilities = false

    private enum TestResult: Identifiable {
        case success, failure(String), useAnyway
        var id: Int { switch self { case .success: return 0; case .failure: return 1; case .useAnyway: return 2 } }
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

    /// Published capability checks inform setup; Use Anyway explicitly bypasses them.
    private var selectedModelSupportsVision: Bool {
        return selectedDiscoveredModel?.supportsTextAndImage == true
    }

    private var visionWarning: String? {
        guard hasLoadedModels else { return nil }
        guard let m = selectedDiscoveredModel else {
            return "“\(model)” isn’t in the loaded list. Pick a model from the list so Fueli can confirm it supports food photos."
        }
        switch m.capabilities {
        case .none:
            return "Couldn’t determine whether “\(m.id)” supports images — from provider metadata, official model cards, or models.dev. Pick a model with a confirmed Vision capability."
        case .some(let caps) where !caps.contains(.image):
            return "Image input is not confirmed for “\(m.id)”. Fueli needs a vision-capable model to analyze food photos."
        case .some(let caps) where !caps.contains(.text):
            return "Text input is not confirmed for “\(m.id)”, which Fueli needs."
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

                if isLookingUpCapabilities { ProgressView("Looking up published model capabilities…") }
                if let source = selectedDiscoveredModel?.capabilitySource {
                    Text("Capability source: " + source).font(.caption).foregroundStyle(.secondary)
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
                    Text("\(discoveredModels.count) models loaded. ✓ marks models confirmed to support text + images (from provider metadata, official model cards, or models.dev); ⚠︎ marks the rest. Published model capabilities may differ from what your gateway enables.")
                }
            }

            Section {
                Picker("Meal analysis", selection: $assumptionLevel) {
                    ForEach(AssumptionLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }

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
                .disabled(!canSave || !selectedModelSupportsVision)
                if !selectedModelSupportsVision {
                    Button("Use Anyway") { testResult = .useAnyway }
                        .disabled(!canLoadModels || model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                }
            } footer: {
                if !selectedModelSupportsVision {
                    Text("Vision support is unconfirmed. You can choose another model or use this model anyway.")
                        .foregroundStyle(.red)
                } else {
                    Text("Your API key is stored securely in the iOS Keychain and is only sent to the configured provider.")
                }
            }
        }
        .themedScreenBackground()
        .navigationTitle("AI Provider")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model) {
            let requestedID = model
            guard !requestedID.isEmpty else { return }
            isLookingUpCapabilities = true
            defer { if model == requestedID { isLookingUpCapabilities = false } }
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            let current = selectedDiscoveredModel ?? .init(id: requestedID, capabilities: nil)
            let published = await AINutritionService.lookupPublishedCapabilities(for: current)
            guard !Task.isCancelled, requestedID == model else { return }
            discoveredModels.removeAll { $0.id == requestedID }
            discoveredModels.append(published)
            discoveredModels.sort { $0.id < $1.id }
        }
        .alert(item: $testResult) { result in
            switch result {
            case .useAnyway:
                return Alert(title: Text("Use this model anyway?"),
                    message: Text("Text and vision support could not be confirmed for this endpoint. AI features may not work properly, including photo analysis. Continue with this model?"),
                    primaryButton: .default(Text("Use Anyway")) { save(); testConnection() },
                    secondaryButton: .cancel())
            case .success:
                return Alert(title: Text("Connected"), message: Text("A text request succeeded. Photo support still depends on your endpoint."), dismissButton: .default(Text("OK")))
            case .failure(let message):
                return Alert(title: Text("Connection Failed"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var canSave: Bool {
        !apiKey.isEmpty && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (preset != .custom || !baseURL.isEmpty) && !isTesting && !isLoadingModels && !isLookingUpCapabilities
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
                    guard preset == p, effectiveBaseURL == base, apiKey == key else {
                        isLoadingModels = false
                        return
                    }
                    isLoadingModels = false
                    discoveredModels = models
                    if models.isEmpty {
                        modelLoadError = "The provider returned no models."
                    }
                    // Refresh the selected model independently of possibly stale gateway metadata.
                    let selectedID = model
                    Task {
                        let current = models.first(where: { $0.id == selectedID }) ?? .init(id: selectedID, capabilities: nil)
                        let published = await AINutritionService.lookupPublishedCapabilities(for: current)
                        guard model == selectedID else { return }
                        discoveredModels.removeAll { $0.id == selectedID }
                        discoveredModels.append(published)
                        discoveredModels.sort { $0.id < $1.id }
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
