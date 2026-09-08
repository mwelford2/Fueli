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
        let userText = userNote?.isEmpty == false
            ? "Analyze the food in this photo. Additional context from the user: \(userNote!)"
            : "Analyze the food in this photo."
        return try await runAnalysis(userText: userText, imageBase64: base64)
    }

    func analyzeDescription(_ text: String) async throws -> NutritionFacts {
        try await runAnalysis(userText: "Analyze this meal description: \(text)", imageBase64: nil)
    }

    // Simple connectivity check used by the Settings screen's "Test Connection" action.
    func testConnection() async throws {
        _ = try await runRawText(userText: "Hi there!", imageBase64: nil)
    }

    // MARK: - Dispatch

    func runAnalysis(userText: String, imageBase64: String?, prompt: String? = nil) async throws -> NutritionFacts {
        let response = try await runRawText(userText: userText, imageBase64: imageBase64, prompt: prompt)
        
        if userText.contains("Analyze the food in this photo") {
            return try await USDAapiCaller.shared.analyzeFood(description: "", imageBase64: imageBase64, AIResponse: response)
        }
        
        let description = userText.replacingOccurrences(of: "Analyze this meal description: ", with: "")
        
        return try await USDAapiCaller.shared.analyzeFood(description: description, imageBase64: "", AIResponse: response)
    }

    /// Calls the AI and returns the raw response string without JSON parsing.
    /// Use this for prompts that don't return a NutritionAnalysisResult (e.g. the FDC candidate classifier).
    func runRawText(userText: String, imageBase64: String?, prompt: String? = nil) async throws -> String {
        let config = self.config
        guard config.isConfigured else { throw AIServiceError.notConfigured }
        guard URL(string: config.normalizedBaseURL) != nil else { throw AIServiceError.invalidBaseURL }
        if config.preset.isOpenAICompatible {
            return try await callOpenAICompatible(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt)
        } else {
            return try await callAnthropic(config: config, userText: userText, imageBase64: imageBase64, systemPrompt: prompt)
        }
    }

    // MARK: - OpenAI-compatible (OpenAI, Grok, custom/school gateways)

    private func callOpenAICompatible(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil) async throws -> String {
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
            "temperature": 0.2,
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

    private func callAnthropic(config: AIProviderConfig, userText: String, imageBase64: String?, systemPrompt: String? = nil) async throws -> String {
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
