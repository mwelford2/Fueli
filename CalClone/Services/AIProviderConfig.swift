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

/// Persisted (non-secret) AI provider settings. The API key itself lives in the Keychain.
struct AIProviderConfig: Codable, Equatable {
    var preset: AIProviderPreset
    var baseURL: String
    var model: String

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
