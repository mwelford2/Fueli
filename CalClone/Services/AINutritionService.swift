import Foundation
import UIKit

/// Talks to whatever AI provider the user has configured (OpenAI, Anthropic, Grok, or a
/// custom/school OpenAI-compatible gateway) to turn a food photo or text description into
/// a structured nutrition estimate.
final class AINutritionService {
    static let shared = AINutritionService()

    private let systemPrompt = """
    You are a nutrition estimation assistant embedded in a calorie tracking app. \
    Given a photo of food and/or a text description, identify the food and estimate its \
    nutritional content PER SINGLE SERVING. Account for visible portion size to determine \
    a reasonable single-serving size; describe it in "serving_description" (e.g. "1 cup (240 ml)", \
    "1 slice (28 g)", "1 medium banana"). If multiple distinct items are present, treat the whole \
    plate as one combined serving. All numeric values must be for that ONE serving only — do NOT \
    multiply by an implied quantity. Respond with ONLY a single JSON object, no prose, no markdown \
    fences, matching exactly this shape:
    {"name": string, "calories": integer, "protein_g": number, "carbs_g": number, "fat_g": number, "fiber_g": number, "serving_description": string}
    """

    private var config: AIProviderConfig { AIProviderConfig.load() }

    // MARK: - Public API

    func analyzePhoto(_ image: UIImage, userNote: String?) async throws -> NutritionAnalysisResult {
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

    func analyzeDescription(_ text: String) async throws -> NutritionAnalysisResult {
        try await runAnalysis(userText: "Analyze this meal description: \(text)", imageBase64: nil)
    }

    /// Simple connectivity check used by the Settings screen's "Test Connection" action.
    func testConnection() async throws {
        _ = try await runAnalysis(userText: "Analyze this meal description: one medium banana", imageBase64: nil)
    }

    // MARK: - Dispatch

    private func runAnalysis(userText: String, imageBase64: String?) async throws -> NutritionAnalysisResult {
        let config = self.config
        guard config.isConfigured else { throw AIServiceError.notConfigured }
        guard URL(string: config.normalizedBaseURL) != nil else { throw AIServiceError.invalidBaseURL }

        let rawText: String
        if config.preset.isOpenAICompatible {
            rawText = try await callOpenAICompatible(config: config, userText: userText, imageBase64: imageBase64)
        } else {
            rawText = try await callAnthropic(config: config, userText: userText, imageBase64: imageBase64)
        }
        return try Self.parseResult(from: rawText)
    }

    // MARK: - OpenAI-compatible (OpenAI, Grok, custom/school gateways)

    private func callOpenAICompatible(config: AIProviderConfig, userText: String, imageBase64: String?) async throws -> String {
        guard let url = URL(string: config.normalizedBaseURL + "/chat/completions") else {
            throw AIServiceError.invalidBaseURL
        }

        // When an image is present, merge the system prompt into the user content array
        // instead of using a separate system message. Some vLLM-backed gateways (e.g.
        // NaviGator Toolkit) silently drop image content when a string-typed system
        // message is combined with an array-typed user message.
        let messages: [[String: Any]]
        if let imageBase64 {
            let userContent: [[String: Any]] = [
                ["type": "text", "text": systemPrompt + "\n\n" + userText],
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]]
            ]
            messages = [["role": "user", "content": userContent]]
        } else {
            messages = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [["type": "text", "text": userText]]]
            ]
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0.2,
            "max_tokens": 500
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
        return content
    }

    // MARK: - Anthropic native

    private func callAnthropic(config: AIProviderConfig, userText: String, imageBase64: String?) async throws -> String {
        guard let url = URL(string: config.normalizedBaseURL + "/messages") else {
            throw AIServiceError.invalidBaseURL
        }

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
            "max_tokens": 500,
            "system": systemPrompt,
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
    private static func resized(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
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
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
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
