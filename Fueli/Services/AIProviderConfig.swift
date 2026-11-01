import Foundation

enum AIProviderPreset: String, Codable, CaseIterable, Identifiable {
    case openAI, anthropic, gemini, grok, custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic (Claude)"
        case .gemini: return "Google (Gemini)"
        case .grok: return "xAI (Grok)"
        case .custom: return "Custom / School Endpoint"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .grok: return "https://api.x.ai/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-5"
        case .gemini: return "gemini-2.0-flash"
        case .grok: return "grok-4"
        case .custom: return "gpt-4o"
        }
    }

    /// Whether this preset speaks the OpenAI-compatible /chat/completions wire format.
    /// Anthropic's native API uses a different schema; everything else (including most
    /// custom/school gateways "using OpenAI documentation") is treated as OpenAI-compatible.
    var isOpenAICompatible: Bool { self != .anthropic }
}

/// How aggressively the meal-analysis model should fill in unknowns on its own versus
/// stopping to ask the user a clarifying question.
enum AssumptionLevel: String, Codable, CaseIterable, Identifiable {
    /// Always ask at least one clarifying question before returning a final estimate.
    case alwaysAsk
    /// Ask whenever anything material is uncertain.
    case ask
    /// Only ask when an unknown could swing calories substantially. (Default.)
    case balanced
    /// Never ask — always return a best-guess estimate.
    case assume

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alwaysAsk: return "Always ask"
        case .ask: return "Ask often"
        case .balanced: return "Balanced"
        case .assume: return "Assume freely"
        }
    }

    var detail: String {
        switch self {
        case .alwaysAsk: return "Always asks at least one follow-up before estimating."
        case .ask: return "Asks whenever something meaningful is unclear."
        case .balanced: return "Only asks when an unknown could change calories a lot."
        case .assume: return "Never asks — always gives a best guess."
        }
    }

    /// Instruction block injected into the decomposition prompt.
    var promptDirective: String {
        switch self {
        case .alwaysAsk:
            return """
            ASSUMPTION POLICY: alwaysAsk. You must set needs_confirmation to true and \
            provide a clarifying_question on the first pass, even if your estimate is \
            fairly confident — pick the single unknown that most affects calories. Only \
            after the user has answered at least one question may you set \
            needs_confirmation to false.
            """
        case .ask:
            return """
            ASSUMPTION POLICY: ask. Prefer asking over guessing. If any component's \
            preparation, portion, added fat, sauce, or ingredient identity is uncertain, \
            set needs_confirmation to true and ask about the highest-impact one.
            """
        case .balanced:
            return """
            ASSUMPTION POLICY: balanced. Ask only when an unknown could change the total \
            calorie estimate by roughly 15% or more (e.g. fried vs grilled, dressing on a \
            salad, whole vs skim milk). Otherwise assume a sensible default and record it \
            in assumptions.
            """
        case .assume:
            return """
            ASSUMPTION POLICY: assume. Never set needs_confirmation to true and always \
            leave clarifying_question null. Make the most likely assumption for every \
            unknown and record each in assumptions.
            """
        }
    }
}

/// Persisted (non-secret) AI provider settings. The API key itself lives in the Keychain.
struct AIProviderConfig: Codable, Equatable {
    var preset: AIProviderPreset
    var baseURL: String
    var model: String
    var assumptionLevel: AssumptionLevel = .balanced

    private enum CodingKeys: String, CodingKey {
        case preset, baseURL, model, assumptionLevel
    }

    init(preset: AIProviderPreset, baseURL: String, model: String, assumptionLevel: AssumptionLevel = .balanced) {
        self.preset = preset
        self.baseURL = baseURL
        self.model = model
        self.assumptionLevel = assumptionLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decode(AIProviderPreset.self, forKey: .preset)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        // Older stored configs won't have this key.
        assumptionLevel = try c.decodeIfPresent(AssumptionLevel.self, forKey: .assumptionLevel) ?? .balanced
    }

    static let userDefaultsKey = "ai_provider_config"
    static let keychainAPIKeyAccount = "ai_provider_api_key"
    static let keychainBaseURLAccount = "ai_provider_base_url"

    static var `default`: AIProviderConfig {
        AIProviderConfig(preset: .openAI, baseURL: AIProviderPreset.openAI.defaultBaseURL, model: AIProviderPreset.openAI.defaultModel)
    }

    static func load() -> AIProviderConfig {
        guard
            let data = UserDefaults.standard.data(forKey: userDefaultsKey),
            let decoded = try? JSONDecoder().decode(AIProviderConfig.self, from: data)
        else {
            // UserDefaults wiped — reconstruct from Keychain if possible
            var fallback = AIProviderConfig.default
            if let url = KeychainStore.read(account: keychainBaseURLAccount), !url.isEmpty {
                fallback.baseURL = url
            }
            return fallback
        }
        var config = decoded
        // Keychain is more durable than UserDefaults; prefer it when present
        if let url = KeychainStore.read(account: keychainBaseURLAccount), !url.isEmpty {
            config.baseURL = url
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
        if baseURL.isEmpty {
            KeychainStore.delete(account: Self.keychainBaseURLAccount)
        } else {
            KeychainStore.save(baseURL, account: Self.keychainBaseURLAccount)
        }
    }

    var apiKey: String {
        get { KeychainStore.read(account: Self.keychainAPIKeyAccount) ?? "" }
        nonmutating set {
            if newValue.isEmpty {
                KeychainStore.delete(account: Self.keychainAPIKeyAccount)
            } else {
                KeychainStore.save(newValue, account: Self.keychainAPIKeyAccount)
            }
        }
    }

    var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !apiKey.isEmpty
    }

    /// Normalized base URL with no trailing slash, so we can safely append paths.
    var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
