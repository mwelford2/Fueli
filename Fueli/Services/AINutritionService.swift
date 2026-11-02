import Foundation
import UIKit

enum Error {
    case runtimeError(String)
}

/// Talks to whatever AI provider the user has configured (OpenAI, Anthropic, Grok, or a
/// custom/school OpenAI-compatible gateway) to turn a food photo or text description into
/// a structured nutrition estimate.
final class AINutritionService {
    static let shared = AINutritionService()
    private let session: URLSession
    private let configuration: () -> AIProviderConfig
    private let apiKeyProvider: () -> String

    init(session: URLSession = .shared,
         configuration: @escaping () -> AIProviderConfig = { AIProviderConfig.load() },
         apiKeyProvider: (() -> String)? = nil) {
        self.session = session
        self.configuration = configuration
        self.apiKeyProvider = apiKeyProvider ?? { configuration().apiKey }
    }

    private let systemPrompt = loadPrompt(named: "fdc_ingredient_prompt")
    
    private static func loadPrompt(named name: String, ext: String = "md") -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md")
        else {
            assertionFailure("Missing \(name).\(ext)")
            return ""
        }
        
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            assertionFailure("Failed to read \(name).md")
            return ""
        }
    }
            
    private var config: AIProviderConfig { configuration() }

    // MARK: - Public API

    func analyzePhoto(_ image: UIImage, userNote: String?) async throws -> NutritionFacts {
        let resized = Self.resized(image, maxDimension: 1024)
        guard let jpegData = resized.jpegData(compressionQuality: 0.7) else {
            throw AIServiceError.requestFailed("Could not encode image.")
        }
        let base64 = jpegData.base64EncodedString()
        let input = AnalysisInput(userText: userNote, imageBase64: base64, kind: .photo)
        let decomposition = try await decompose(input, clarifications: [])
        return try await resolveNutrition(from: decomposition, imageBase64: base64)
    }

    func analyzeDescription(_ text: String) async throws -> NutritionFacts {
        let input = AnalysisInput(userText: text, imageBase64: nil, kind: .description)
        let decomposition = try await decompose(input, clarifications: [])
        return try await resolveNutrition(from: decomposition, imageBase64: nil)
    }

    // Simple connectivity check used by the Settings screen's "Test Connection" action.
    func testConnection() async throws {
        _ = try await runRawText(userText: "Hi there!", imageBase64: nil)
    }

    // MARK: - Model discovery

    /// A model advertised by the configured provider. `capabilities` is nil when we
    /// have no trustworthy source for them — we never guess from the name.
    struct DiscoveredModel: Identifiable, Equatable, Hashable {
        let id: String
        /// nil == unknown. Non-nil == known from the provider's own metadata or models.dev.
        var capabilities: Set<ModelCapability>?
        var capabilitySource: String? = nil
        var hasCompleteCapabilityMetadata = true
        var unsupportedCapabilities: Set<ModelCapability> = []

        var capabilityLabel: String {
            guard let capabilities else { return "Capabilities unknown" }
            let known = ModelCapability.allCases
                .filter { capabilities.contains($0) }
                .map(\.shortLabel)
            let label = known.isEmpty ? "Capabilities unknown" : known.joined(separator: " · ")
            return hasCompleteCapabilityMetadata ? label : label + " · Other inputs unknown"
        }

        /// True only when we positively know the model accepts both text and images.
        var supportsTextAndImage: Bool {
            guard let capabilities else { return false }
            return capabilities.contains(.text) && capabilities.contains(.image)
        }
    }

    enum ModelCapability: String, CaseIterable {
        case text, image, audio, video

        var shortLabel: String {
            switch self {
            case .text: return "Text"
            case .image: return "Vision"
            case .audio: return "Audio"
            case .video: return "Video"
            }
        }
    }

    /// Fetches the model list from an arbitrary base URL + key (used from Settings
    /// before the config is saved). Returns models sorted by id.
    func fetchModels(baseURL: String, apiKey: String, preset: AIProviderPreset) async throws -> [DiscoveredModel] {
        let normalized = { () -> String in
            var u = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while u.hasSuffix("/") { u.removeLast() }
            return u
        }()
        guard !normalized.isEmpty, !apiKey.isEmpty else { throw AIServiceError.notConfigured }

        func makeRequest(_ path: String) -> URLRequest {
            var request = URLRequest(url: URL(string: normalized + path)!)
            request.timeoutInterval = 20
            if preset == .anthropic {
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            } else {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            return request
        }

        var models: [DiscoveredModel]

        // For custom / self-hosted gateways, try LiteLLM's richer /model/info first —
        // it reports per-model capability flags (supports_vision, supports_audio_input,
        // …). Fall back to the standard /models list if that route is blocked or 404s.
        if preset == .custom, let liteLLM = try? await Self.fetch(makeRequest("/model/info")) {
            let parsed = Self.parseLiteLLMModelInfo(liteLLM)
            models = parsed.isEmpty ? Self.parseModelList(try await Self.fetch(makeRequest("/models"))) : parsed
        } else {
            // Anthropic native lives at /v1/models with x-api-key; OpenAI-compatible at
            // {base}/models with a bearer token. `normalizedBaseURL` for Anthropic
            // already ends in /v1, so /models is correct for both.
            models = Self.parseModelList(try await Self.fetch(makeRequest("/models")))
        }

        // Sparse supports_* flags describe individual capabilities, not an exhaustive list.
        // Consult exact, documented model cards first, then the community catalog.
        models = models.map { Self.resolveCapabilities($0, database: nil) }
        if models.contains(where: { !$0.hasCompleteCapabilityMetadata || $0.capabilities == nil }),
           let db = try? await Self.loadModelsDevDatabase() {
            models = models.map { Self.resolveCapabilities($0, database: db) }
        }

        return models
    }

    /// Reviewed against Google's official model card, 2026-10-30. Exact identifiers only;
    /// this documents the base model, not a guarantee that a gateway enables every input.
    static func resolveCapabilities(_ model: DiscoveredModel, database: ModelsDevDatabase?) -> DiscoveredModel {
        var result = model
        let id = model.id.lowercased()
        let reference: Set<ModelCapability>?
        if ["gemma-4-31b-it", "google/gemma-4-31b-it"].contains(id) {
            reference = [.text, .image]
            result.capabilitySource = "Google Gemma 4 model card · https://ai.google.dev/gemma/docs/core/model_card_4"
        } else {
            reference = database?.capabilities(forModelID: model.id)
            if reference != nil { result.capabilitySource = "models.dev · https://models.dev" }
        }
        if let reference {
            result.capabilities = reference
            result.hasCompleteCapabilityMetadata = true
        }
        return result
    }

    /// Only exact repository IDs or reviewed publisher aliases; no fuzzy HF search.
    static func huggingFaceRepository(for id: String) -> String? {
        if ["gemma-4-31b-it", "google/gemma-4-31b-it"].contains(id.lowercased()) {
            return "google/gemma-4-31B-it"
        }
        let parts = id.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return id
    }

    static func capabilitiesFromHuggingFace(_ data: Data, repository: String, modelID: String) throws -> DiscoveredModel? {
        struct Metadata: Decodable {
            let id: String
            let pipeline_tag: String?
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: data)
        guard metadata.id.lowercased() == repository.lowercased() else { return nil }
        let capabilities: Set<ModelCapability>
        switch metadata.pipeline_tag {
        case "image-text-to-text": capabilities = [.text, .image]
        case "text-generation", "text2text-generation": capabilities = [.text]
        case "image-to-text": capabilities = [.image]
        case "video-text-to-text": capabilities = [.text, .video]
        default: return nil
        }
        return DiscoveredModel(id: modelID, capabilities: capabilities,
            capabilitySource: "Hugging Face model metadata · https://huggingface.co/" + metadata.id)
    }

    /// Public metadata only. Provider keys and endpoint URLs are never sent to HF.
    static func lookupPublishedCapabilities(for model: DiscoveredModel, session: URLSession = .shared) async -> DiscoveredModel {
        if let repository = huggingFaceRepository(for: model.id),
           let url = URL(string: "https://huggingface.co/api/models/" + repository) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let published = try capabilitiesFromHuggingFace(data, repository: repository, modelID: model.id) {
                    return published
                }
            } catch { /* Offline, gated, or unknown metadata: retain documented fallbacks. */ }
        }
        if Task.isCancelled { return model }
        let reviewed = resolveCapabilities(model, database: nil)
        if reviewed.capabilitySource != model.capabilitySource { return reviewed }
        let database = try? await loadModelsDevDatabase()
        return resolveCapabilities(model, database: database)
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.requestFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            // Gateways can echo credentials, photographs or prompts in error bodies.
            // Keep diagnostics actionable without displaying private response content.
            let message: String
            switch http.statusCode {
            case 401, 403: message = "Check the API key and model permissions in Settings → AI Provider."
            case 429: message = "The provider is rate limited. Wait and retry."
            case 500...599: message = "The provider is temporarily unavailable. Retry later."
            default: message = "Check the endpoint, model and provider settings, then retry."
            }
            throw AIServiceError.httpError(http.statusCode, message)
        }
        return data
    }

    /// LiteLLM `GET /model/info` → `{ "data": [{ "model_name": "...",
    /// "model_info": { "supports_vision": true, "supports_audio_input": false, ... } }] }`
    static func parseLiteLLMModelInfo(_ data: Data) -> [DiscoveredModel] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["data"] as? [[String: Any]]
        else { return [] }

        var models: [DiscoveredModel] = []
        for entry in entries {
            let id = (entry["model_name"] as? String) ?? (entry["model"] as? String) ?? ""
            guard !id.isEmpty else { continue }
            let info = (entry["model_info"] as? [String: Any]) ?? [:]

            // LiteLLM always reports a `mode`; when present we trust its capability flags.
            guard let mode = (info["mode"] as? String)?.lowercased() else {
                var metadata = info
                metadata["id"] = id
                if let data = try? JSONSerialization.data(withJSONObject: ["data": [metadata]]),
                   let partial = parseModelList(data).first {
                    models.append(partial)
                } else {
                    models.append(DiscoveredModel(id: id, capabilities: nil, hasCompleteCapabilityMetadata: false))
                }
                continue
            }

            var caps: Set<ModelCapability> = []
            switch mode {
            case "chat", "completion", "responses":
                caps.insert(.text)
                if info["supports_vision"] as? Bool == true { caps.insert(.image) }
                if info["supports_audio_input"] as? Bool == true { caps.insert(.audio) }
                if info["supports_video_input"] as? Bool == true { caps.insert(.video) }
            case "audio_transcription", "audio_speech":
                caps.insert(.audio)
            case "image_generation":
                caps.insert(.image)
            default:
                // embedding, rerank, moderation, … — not a chat model, no input modalities.
                break
            }
            models.append(DiscoveredModel(id: id, capabilities: caps, capabilitySource: "Provider /model/info"))
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    /// Parses the OpenAI / Anthropic `{data:[{id,...}]}` shape. Reads capability hints
    /// only when the provider actually supplies them (OpenRouter `architecture`,
    /// LiteLLM flat booleans, Anthropic `capabilities`); otherwise leaves capabilities
    /// nil for a later models.dev lookup. Never infers from the id.
    static func parseModelList(_ data: Data) -> [DiscoveredModel] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = root["data"] as? [[String: Any]]
        else { return [] }

        var models: [DiscoveredModel] = []
        for entry in entries {
            guard let id = entry["id"] as? String, !id.isEmpty else { continue }
            var caps: Set<ModelCapability> = []
            var haveCapabilityData = false
            var complete = false
            var unsupported: Set<ModelCapability> = []

            // OpenRouter-style: architecture.input_modalities / modality ("text+image->text")
            if let arch = entry["architecture"] as? [String: Any] {
                if let mods = arch["input_modalities"] as? [String] {
                    caps.formUnion(mapModalityTokens(mods)); haveCapabilityData = true; complete = true
                }
                if let modality = arch["modality"] as? String {
                    let inputSide = modality.components(separatedBy: "->").first ?? modality
                    caps.formUnion(mapModalityTokens(inputSide.components(separatedBy: CharacterSet(charactersIn: "+ ,"))))
                    haveCapabilityData = true
                    complete = true
                }
            }
            // LiteLLM-style flat booleans on the model object itself.
            for (key, capability) in [("supports_vision", ModelCapability.image),
                                      ("supports_audio_input", .audio), ("supports_video_input", .video)] {
                if let supported = entry[key] as? Bool {
                    haveCapabilityData = true
                    if supported { caps.insert(capability) } else { unsupported.insert(capability) }
                }
            }
            if let mode = entry["mode"] as? String, ["chat", "completion", "responses"].contains(mode.lowercased()) {
                caps.insert(.text)
                haveCapabilityData = true
            }
            // Anthropic capabilities object (fields are an open set).
            if let anthropicCaps = entry["capabilities"] as? [String: Any] {
                haveCapabilityData = true
                if anthropicCaps["vision"] as? Bool == true { caps.insert(.image) }
                caps.insert(.text)
            }

            models.append(DiscoveredModel(id: id, capabilities: haveCapabilityData ? caps : nil,
                capabilitySource: haveCapabilityData ? "Provider /models" : nil,
                hasCompleteCapabilityMetadata: complete, unsupportedCapabilities: unsupported))
        }
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private static func mapModalityTokens(_ tokens: [String]) -> Set<ModelCapability> {
        var caps: Set<ModelCapability> = []
        for token in tokens.map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch token {
            case "text": caps.insert(.text)
            case "image", "vision": caps.insert(.image)
            case "audio", "speech": caps.insert(.audio)
            case "video": caps.insert(.video)
            default: break
            }
        }
        return caps
    }

    // MARK: models.dev capability database

    /// A parsed snapshot of models.dev's `api.json`, indexed by bare model id. The
    /// same id can appear under several providers with differing modalities — we
    /// retain only input modalities shared by all matching catalog entries.
    struct ModelsDevDatabase {
        /// bare model id (lowercased) → intersection of input modalities seen for it
        private let byID: [String: Set<ModelCapability>]

        init(json: Data) throws {
            guard let providers = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
                throw AIServiceError.unparsableResponse("models.dev: not a JSON object")
            }
            var acc: [String: Set<ModelCapability>] = [:]
            for (_, providerAny) in providers {
                guard
                    let provider = providerAny as? [String: Any],
                    let modelMap = provider["models"] as? [String: Any]
                else { continue }
                for (modelID, modelAny) in modelMap {
                    guard
                        let model = modelAny as? [String: Any],
                        let modalities = model["modalities"] as? [String: Any],
                        let input = modalities["input"] as? [String]
                    else { continue }
                    let caps = AINutritionService.mapModalityTokens(input)
                    let key = modelID.lowercased()
                    acc[key] = acc[key].map { $0.intersection(caps) } ?? caps
                }
            }
            self.byID = acc
        }

        /// Exact identifier lookup, allowing a provider namespace but never stripping
        /// version/date suffixes that may distinguish models with different capabilities.
        func capabilities(forModelID id: String) -> Set<ModelCapability>? {
            let lower = id.lowercased()
            if let exact = byID[lower] { return exact }

            let bare = lower.split(separator: "/").last.map(String.init) ?? lower
            if let m = byID[bare] { return m }

            return nil
        }
    }

    private static var cachedModelsDevDatabase: ModelsDevDatabase?

    static func loadModelsDevDatabase() async throws -> ModelsDevDatabase {
        if let cachedModelsDevDatabase { return cachedModelsDevDatabase }
        guard let url = URL(string: "https://models.dev/api.json") else {
            throw AIServiceError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.assumesHTTP3Capable = false
        let data = try await Self.fetch(request)
        let db = try ModelsDevDatabase(json: data)
        cachedModelsDevDatabase = db
        return db
    }

    // MARK: - Clarification flow

    /// One turn of the analyze conversation: the meal input plus every clarifying
    /// question the model has asked and the user's answer to each.
    struct AnalysisInput {
        enum Kind { case photo, description }
        var userText: String?
        var imageBase64: String?
        var kind: Kind
    }

    struct Clarification: Identifiable, Equatable {
        let id = UUID()
        var question: String
        var answer: String
    }

    /// Runs the decomposition model once. Does NOT touch the USDA API — returns the
    /// model's structured breakdown, which may carry a `clarifyingQuestion`.
    func decompose(_ input: AnalysisInput, clarifications: [Clarification]) async throws -> NutritionAnalysisResult {
        if input.kind == .photo {
            let prompt = """
            Describe the meal image for user review. Return ONLY JSON with:
            {"dishName":"string","observedFacts":["string"],"estimates":["string"],"unknowns":["string"],
            "items":[{"name":"string","estimatedGrams":100.0,"preparation":"cooked/grilled/sauce/oil details or unknown","measureBasis":"raw|cooked|as_packaged"}],"clarifyingQuestion":null}
            Separate observations from estimates and unknowns. Include visible components, serving count, sauces, oils, toppings,
            preparation and hidden-ingredient uncertainties. Grams are estimates, not measurements without a scale reference.
            Ask at most one material clarification question; respect supplied answers. Do NOT produce calories, nutrients or database queries.
            """
            let questionPolicy: String
            switch config.assumptionLevel {
            case .assume: questionPolicy = "Do not ask questions; clarifyingQuestion must be null. Record remaining unknowns."
            case .alwaysAsk where clarifications.isEmpty: questionPolicy = "Ask one material clarifyingQuestion before finalizing the description."
            case .ask: questionPolicy = "Ask about the most important uncertain ingredient, preparation, or quantity."
            default: questionPolicy = "Ask only if an uncertainty could materially change nutrition; otherwise record unknowns."
            }
            let answers = clarifications.map { $0.question + ": " + $0.answer }.joined(separator: "\n")
            let raw = try await runRawText(userText: (input.userText ?? "Describe this meal.") + "\n" + answers,
                imageBase64: input.imageBase64, prompt: prompt + "\n" + questionPolicy, outputContract: .description)
            let clean = NutritionAnalysisResult.stripMarkdownFences(raw)
            let description = try JSONDecoder().decode(PhotoMealDescription.self, from: Data(clean.utf8))
            return try description.reviewResult()
        }
        let level = config.assumptionLevel
        let systemPrompt = self.systemPrompt.replacingOccurrences(
            of: "{{ASSUMPTION_POLICY}}",
            with: level.promptDirective
        )

        var userText: String
        switch input.kind {
        case .photo:
            userText = input.userText?.isEmpty == false
                ? "Analyze the food in this photo. Additional context from the user: \(input.userText!)"
                : "Analyze the food in this photo."
        case .description:
            userText = "Analyze this meal description: \(input.userText ?? "")"
        }

        if !clarifications.isEmpty {
            let block = clarifications
                .map { "Q: \($0.question)\nA: \($0.answer)" }
                .joined(separator: "\n\n")
            userText += "\n\nClarifications so far:\n\(block)"
        }

        let raw = try await runRawText(userText: userText, imageBase64: input.imageBase64, prompt: systemPrompt, outputContract: .lookupPlan)
        return try USDAapiCaller.parseNutritionResult(from: raw)
    }

    /// Turns a finalized decomposition into concrete numbers via the USDA API.
    func resolveNutrition(from result: NutritionAnalysisResult, imageBase64: String?, selections: [String: USDAapiCaller.FDCFood] = [:]) async throws -> NutritionFacts {
        let plan = try await planNutritionLookup(from: result)
        return try await USDAapiCaller.shared.analyzeFood(result: plan, imageBase64: nil, selections: selections)
    }

    func planNutritionLookup(from result: NutritionAnalysisResult) async throws -> NutritionAnalysisResult {
        // Stage two receives ONLY the user's corrected description, never the image.
        let description = try JSONEncoder().encode(result)
        let instructions = systemPrompt.replacingOccurrences(of: "{{ASSUMPTION_POLICY}}", with: AssumptionLevel.assume.promptDirective)
            + "\nPlan USDA search queries for this corrected structured description. Do not invent nutrition or claim USDA retrieval. Preserve component order and copy every component label EXACTLY; quantities are authoritative. Return the documented JSON contract only."
        var planned: NutritionAnalysisResult?
        for attempt in 0..<2 {
            let text = String(decoding: description, as: UTF8.self) + (attempt == 1 ? "\nPrevious output was invalid. Return strict schema-conforming JSON only." : "")
            let raw = try await runRawText(userText: text, imageBase64: nil, prompt: instructions, outputContract: .lookupPlan)
            if let decoded = try? USDAapiCaller.parseNutritionResult(from: raw), decoded.components.count == result.components.count,
               zip(decoded.components, result.components).allSatisfy({
                   $0.0.label.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare($0.1.label.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
               }) {
                planned = decoded; break
            }
        }
        guard var plan = planned else { throw AIServiceError.requestFailed("The USDA query planner returned invalid output. Correct the description and retry.") }
        for index in result.components.indices {
            plan.components[index].label = result.components[index].label
            plan.components[index].estimatedGrams = result.components[index].estimatedGrams
            plan.components[index].quantity = result.components[index].quantity
            plan.components[index].preparation = result.components[index].preparation
            plan.components[index].measureBasis = result.components[index].measureBasis
            plan.components[index].negligible = result.components[index].negligible
            plan.components[index].brand = result.components[index].brand
        }
        plan.dishName = result.dishName
        return plan
    }

    /// A fixed seed so gateways that honour it (OpenAI, vLLM, most LiteLLM backends)
    /// return the same completion for the same prompt — the main lever for making
    /// repeat analyses of an identical meal match.
    static let deterministicSeed = 8213

    /// Calls the AI and returns the raw response string without JSON parsing.
    /// Use this for prompts that don't return a NutritionAnalysisResult (e.g. the FDC candidate classifier).
    /// `temperature` defaults to 0 for maximum run-to-run consistency.
    func runRawText(userText: String, imageBase64: String?, prompt: String? = nil, temperature: Double = 0, outputContract: MealOutputContract? = nil) async throws -> String {
        let config = self.config
        guard !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !apiKeyProvider().isEmpty else { throw AIServiceError.notConfigured }
        guard let base = URL(string: config.normalizedBaseURL), ["https", "http"].contains(base.scheme?.lowercased() ?? ""),
              base.host != nil, base.user == nil, base.password == nil, base.query == nil, base.fragment == nil else { throw AIServiceError.invalidBaseURL }
        if config.preset.isOpenAICompatible {
            return try await callOpenAICompatible(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt, temperature: temperature, outputContract: outputContract)
        } else {
            return try await callAnthropic(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt, temperature: temperature, outputContract: outputContract)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, Grok, custom/school gateways)

    private func callOpenAICompatible(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil, temperature: Double = 0, outputContract: MealOutputContract? = nil) async throws -> String {
        guard let url = URL(string: config.normalizedBaseURL + "/chat/completions") else {
            throw AIServiceError.invalidBaseURL
        }
        
        let prompt = systemPrompt ?? self.systemPrompt

        // When an image is present, merge the system prompt into the user content array
        // instead of using a separate system message. Some vLLM-backed gateways (e.g.
        // NaviGator Toolkit) silently drop image content when a string-typed system
        // message is combined with an array-typed user message.
        let messages: [[String: Any]]
        if let imageBase64 {
            let userContent: [[String: Any]] = [
                ["type": "text", "text": prompt + "\n\n" + userText],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]]
            ]
            messages = [["role": "user", "content": userContent]]
        } else {
            messages = [
                ["role": "system", "content": prompt],
                ["role": "user", "content": [["type": "text", "text": userText]]]
            ]
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": temperature,
            "top_p": 1,
            "seed": Self.deterministicSeed,
            "max_tokens": 2000
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKeyProvider())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await sendWithStructuredOutput(request, contract: outputContract, anthropic: false)
        try Self.validate(response, data: data)

        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        
        return content
    }

    // MARK: - Anthropic native

    private func callAnthropic(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil, temperature: Double = 0, outputContract: MealOutputContract? = nil) async throws -> String {
        guard let url = URL(string: config.normalizedBaseURL + "/messages") else {
            throw AIServiceError.invalidBaseURL
        }
        
        let prompt = systemPrompt ?? self.systemPrompt

        var userContent: [[String: Any]] = []
        if let imageBase64 {
            userContent.append([
                "type": "image",
                "source": ["type": "base64", "media_type": "image/jpeg", "data": imageBase64]
            ])
        }
        userContent.append(["type": "text", "text": userText])

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 2000,
            "temperature": temperature,
            "top_p": 1,
            "system": prompt,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKeyProvider(), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await sendWithStructuredOutput(request, contract: outputContract, anthropic: true)
        try Self.validate(response, data: data)

        struct MessagesResponse: Decodable {
            struct Block: Decodable { let text: String? }
            let content: [Block]
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        guard let text = decoded.content.compactMap(\.text).first, !text.isEmpty else {
            throw AIServiceError.emptyResponse
        }
        return text
    }

    // MARK: - Shared networking helpers

    /// Retry without the optional provider feature only when the endpoint explicitly
    /// rejects that feature. Authentication, throttling and schema errors are not hidden.
    private func sendWithStructuredOutput(_ original: URLRequest, contract: MealOutputContract?, anthropic: Bool) async throws -> (Data, URLResponse) {
        guard let contract, let originalBody = original.httpBody,
              var body = try JSONSerialization.jsonObject(with: originalBody) as? [String: Any] else {
            return try await send(original)
        }
        if anthropic {
            body["output_config"] = ["format": ["type": "json_schema", "schema": contract.schema]]
        } else {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": contract.name, "strict": true, "schema": contract.schema]]
        }
        var request = original
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(request)
        if let http = response as? HTTPURLResponse,
           Self.rejectsStructuredOutput(status: http.statusCode, data: data, anthropic: anthropic) {
            return try await send(original)
        }
        return (data, response)
    }

    static func rejectsStructuredOutput(status: Int, data: Data, anthropic: Bool) -> Bool {
        guard [400, 422].contains(status) else { return false }
        let message = String(decoding: data, as: UTF8.self).lowercased()
        let parameter = anthropic ? "output_config" : "response_format"
        return (message.contains(parameter) || message.contains("json_schema")) &&
            ["not supported", "unsupported", "does not support", "unknown parameter", "unrecognized"].contains(where: message.contains)
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            var timed = request
            timed.timeoutInterval = 90
            return try await session.data(for: timed)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw AIServiceError.requestFailed(error.localizedDescription)
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            // Gateways can echo credentials, photographs or prompts in error bodies.
            // Keep diagnostics actionable without displaying private response content.
            let message: String
            switch http.statusCode {
            case 401, 403: message = "Check the API key and model permissions in Settings → AI Provider."
            case 429: message = "The provider is rate limited. Wait and retry."
            case 500...599: message = "The provider is temporarily unavailable. Retry later."
            default: message = "Check the endpoint, model and provider settings, then retry."
            }
            throw AIServiceError.httpError(http.statusCode, message)
        }
    }

    /// Scales an image down so its longest side is at most `maxDimension` pixels.
    static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// Strips optional markdown code fences and parses the model's JSON reply.
    static func parseResult(from rawText: String) throws -> NutritionAnalysisResult {
        let text = NutritionAnalysisResult.stripMarkdownFences(rawText)
        guard let firstBrace = text.firstIndex(of: "{"), let lastBrace = text.lastIndex(of: "}") else {
            throw AIServiceError.unparsableResponse(rawText)
        }
        let jsonSubstring = text[firstBrace...lastBrace]
        guard let data = jsonSubstring.data(using: .utf8) else {
            throw AIServiceError.unparsableResponse(rawText)
        }
        do {
            return try JSONDecoder().decode(NutritionAnalysisResult.self, from: data)
        } catch {
            throw AIServiceError.unparsableResponse(rawText)
        }
    }
}
