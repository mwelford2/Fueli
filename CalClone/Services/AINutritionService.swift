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
            
    private var config: AIProviderConfig { AIProviderConfig.load() }

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

        var capabilityLabel: String {
            guard let capabilities else { return "Capabilities unknown" }
            let known = ModelCapability.allCases
                .filter { capabilities.contains($0) }
                .map(\.shortLabel)
            return known.isEmpty ? "No text/image/audio/video input" : known.joined(separator: " · ")
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

        // Fill in unknown capabilities from models.dev — a free, keyless cross-provider
        // model database. Anything still unknown after this stays nil (we never guess).
        if models.contains(where: { $0.capabilities == nil }) {
            let db = try? await Self.loadModelsDevDatabase()
            if let db {
                models = models.map { model in
                    guard model.capabilities == nil else { return model }
                    var updated = model
                    updated.capabilities = db.capabilities(forModelID: model.id)
                    return updated
                }
            }
        }

        return models
    }

    private static func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.requestFailed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AIServiceError.httpError(http.statusCode, body)
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
                models.append(DiscoveredModel(id: id, capabilities: nil))
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
            models.append(DiscoveredModel(id: id, capabilities: caps))
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

            // OpenRouter-style: architecture.input_modalities / modality ("text+image->text")
            if let arch = entry["architecture"] as? [String: Any] {
                if let mods = arch["input_modalities"] as? [String] {
                    caps.formUnion(mapModalityTokens(mods)); haveCapabilityData = true
                }
                if let modality = arch["modality"] as? String {
                    let inputSide = modality.components(separatedBy: "->").first ?? modality
                    caps.formUnion(mapModalityTokens(inputSide.components(separatedBy: CharacterSet(charactersIn: "+ ,"))))
                    haveCapabilityData = true
                }
            }
            // LiteLLM-style flat booleans on the model object itself.
            for key in ["supports_vision", "supports_audio_input", "supports_video_input"] where entry[key] != nil {
                haveCapabilityData = true
            }
            if entry["supports_vision"] as? Bool == true { caps.insert(.image) }
            if entry["supports_audio_input"] as? Bool == true { caps.insert(.audio) }
            if entry["supports_video_input"] as? Bool == true { caps.insert(.video) }
            // Anthropic capabilities object (fields are an open set).
            if let anthropicCaps = entry["capabilities"] as? [String: Any] {
                haveCapabilityData = true
                if anthropicCaps["vision"] as? Bool == true { caps.insert(.image) }
                caps.insert(.text)
            }

            models.append(DiscoveredModel(id: id, capabilities: haveCapabilityData ? caps : nil))
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
    /// union the input modalities so "any provider supports images" wins.
    struct ModelsDevDatabase {
        /// bare model id (lowercased) → union of input modalities seen for it
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
                    acc[key, default: []].formUnion(caps)
                }
            }
            self.byID = acc
        }

        /// Looks up a provider's model id against the database. Only exact matches
        /// (optionally ignoring a `provider/` prefix or a trailing date/version tag)
        /// count — we would rather return nil than a wrong capability set.
        func capabilities(forModelID id: String) -> Set<ModelCapability>? {
            let lower = id.lowercased()
            if let exact = byID[lower] { return exact }

            let bare = lower.split(separator: "/").last.map(String.init) ?? lower
            if let m = byID[bare] { return m }

            // Ignore a trailing version/date tag: "-3.1", ".1", "-20250101", "-v2",
            // "-latest", "-preview". The stem before the boundary must match a db key
            // exactly — no arbitrary prefixes (so "nomic-embed-text-v1.5" won't match
            // an unrelated "nomic-embed-text" chat key).
            for candidate in [lower, bare] {
                if let range = candidate.range(
                    of: #"[-.](?:v?\d[\w.]*|\d{6,8}|latest|preview|instruct|it|chat)$"#,
                    options: .regularExpression
                ) {
                    let stem = String(candidate[..<range.lowerBound])
                    if let m = byID[stem] { return m }
                }
            }
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

        let raw = try await runRawText(userText: userText, imageBase64: input.imageBase64, prompt: systemPrompt)
        return try USDAapiCaller.parseNutritionResult(from: raw)
    }

    /// Turns a finalized decomposition into concrete numbers via the USDA API.
    func resolveNutrition(from result: NutritionAnalysisResult, imageBase64: String?) async throws -> NutritionFacts {
        try await USDAapiCaller.shared.analyzeFood(result: result, imageBase64: imageBase64)
    }

    /// A fixed seed so gateways that honour it (OpenAI, vLLM, most LiteLLM backends)
    /// return the same completion for the same prompt — the main lever for making
    /// repeat analyses of an identical meal match.
    static let deterministicSeed = 8213

    /// Calls the AI and returns the raw response string without JSON parsing.
    /// Use this for prompts that don't return a NutritionAnalysisResult (e.g. the FDC candidate classifier).
    /// `temperature` defaults to 0 for maximum run-to-run consistency.
    func runRawText(userText: String, imageBase64: String?, prompt: String? = nil, temperature: Double = 0) async throws -> String {
        let config = self.config
        guard config.isConfigured else { throw AIServiceError.notConfigured }
        guard URL(string: config.normalizedBaseURL) != nil else { throw AIServiceError.invalidBaseURL }
        if config.preset.isOpenAICompatible {
            return try await callOpenAICompatible(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt, temperature: temperature)
        } else {
            return try await callAnthropic(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt, temperature: temperature)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, Grok, custom/school gateways)

    private func callOpenAICompatible(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil, temperature: Double = 0) async throws -> String {
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
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)
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
        
        print(content)
        return content
    }

    // MARK: - Anthropic native

    private func callAnthropic(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil, temperature: Double = 0) async throws -> String {
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
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await send(request)
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

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.requestFailed(error.localizedDescription)
        }
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AIServiceError.httpError(http.statusCode, body)
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
