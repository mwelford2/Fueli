import Foundation
import Security
import Testing
import UIKit
@testable import Fueli

/// Opt-in locally; mandatory in the release gate. Never print keys/raw responses.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FUELI_RELEASE_LIVE"] == "1"))
struct ReleaseLiveTests {
    struct Secrets: Decodable {
        var baseURL: String; var model: String; var preset: AIProviderPreset
        var apiKey: String; var usdaKey: String?
    }
    static func configuration() throws -> (AIProviderConfig, String) {
        let env = ProcessInfo.processInfo.environment
        if let path = env["FUELI_LIVE_SECRETS_PATH"] {
            let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            return (AIProviderConfig(preset: secrets.preset, baseURL: secrets.baseURL, model: secrets.model, assumptionLevel: .assume), secrets.apiKey)
        }
        var config = AIProviderConfig.load()
        if let path = env["FUELI_EXISTING_CONFIG_PLIST"],
           let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil) as? [String: Any],
           let data = plist[AIProviderConfig.userDefaultsKey] as? Data {
            config = try JSONDecoder().decode(AIProviderConfig.self, from: data)
        }
        config.assumptionLevel = .assume
        var key = config.apiKey
        if key.isEmpty {
            // Normal SDK query only: denied/missing items remain unavailable.
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.matteowelford.calclone.apikey",
                kSecAttrAccount as String: AIProviderConfig.keychainAPIKeyAccount,
                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var result: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                key = String(decoding: data, as: UTF8.self)
            }
        }
        guard !key.isEmpty else { throw AIServiceError.requestFailed("Live AI configuration is unavailable to the com.welford.fueli test host. Supply test configuration through FUELI_LIVE_SECRETS_PATH.") }
        return (config, key)
    }

    static func usdaClient() throws -> USDAapiCaller {
        if let path = ProcessInfo.processInfo.environment["FUELI_LIVE_SECRETS_PATH"] {
            let secrets = try JSONDecoder().decode(Secrets.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            if let key = secrets.usdaKey, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return USDAapiCaller(apiKey: key)
            }
        }
        return .shared
    }

    @Test func requiredSavedAITextConnection() async throws {
        let (config, key) = try Self.configuration()
        let client = AINutritionService(configuration: { config }, apiKeyProvider: { key })
        let reply = try await sanitized { try await client.runRawText(userText: "Reply with exactly OK.", imageBase64: nil, prompt: "Connectivity check. Do not include explanations.") }
        #expect(reply.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().contains("OK"))
    }

    @Test func requiredRealPhotoDescriptionAndCorrectedPlan() async throws {
        let (config, key) = try Self.configuration()
        let client = AINutritionService(configuration: { config }, apiKeyProvider: { key })
        let bundle = Bundle(for: LiveFixtureBundle.self)
        let url = try #require(bundle.url(forResource: "banana", withExtension: "jpg"))
        let original = try #require(UIImage(contentsOfFile: url.path))
        let resized = AINutritionService.resized(original, maxDimension: 1024)
        let image = try #require(resized.jpegData(compressionQuality: 0.7)).base64EncodedString()
        let description = try await sanitized { try await client.decompose(.init(userText: "Describe only the visible food. Quantity is an estimate.", imageBase64: image, kind: .photo), clarifications: []) }
        #expect(description.components.contains { $0.label.lowercased().contains("banana") })
        #expect(!description.assumptions.isEmpty)
        var corrected = description
        let banana = try #require(description.components.first { $0.label.lowercased().contains("banana") })
        corrected.components = [banana]
        corrected.components[0].label = "Banana"
        corrected.components[0].estimatedGrams = 135.5
        corrected.components[0].quantity = Quantity(amount: 135.5, unit: "g")
        corrected.components[0].preparation = "raw"
        corrected.components[0].measureBasis = .raw
        let plan = try await sanitized { try await client.planNutritionLookup(from: corrected) }
        #expect(plan.components[0].label == "Banana")
        #expect(plan.components[0].estimatedGrams == 135.5)
        #expect(plan.components[0].measureBasis == .raw)
        #expect(!plan.components[0].fdcQuery.isEmpty)
    }

    @Test func requiredDescribedMealStructuredComponents() async throws {
        let (config, key) = try Self.configuration()
        let client = AINutritionService(configuration: { config }, apiKeyProvider: { key })
        let result = try await sanitized { try await client.decompose(.init(userText: "One everything bagel (105 g) with 28 g plain cream cheese. No butter or oil.", imageBase64: nil, kind: .description), clarifications: []) }
        #expect(result.components.contains { $0.label.lowercased().contains("bagel") })
        #expect(result.components.contains { $0.label.lowercased().contains("cream") && $0.label.lowercased().contains("cheese") })
        #expect(result.components.allSatisfy { $0.estimatedGrams.isFinite && $0.estimatedGrams > 0 })
    }

    @Test func requiredUSDAGenericSearchAndDetails() async throws {
        let client = try Self.usdaClient()
        guard !client.APIKey.isEmpty else { throw AIServiceError.requestFailed("A USDA test key is required for release.") }
        let response = try await client.search(query: "banana raw", dataTypes: ["SR Legacy"])
        let match = try USDAapiCaller.matchingFood(foods: response.foods, query: "banana raw")
        let values = try await client.foodDetail(id: match.fdcId).coreValues()
        #expect([1008, 1003, 1004, 1005, 1079].allSatisfy { values[$0] != nil })
        #expect((values[1008] ?? 0) > 0)
    }

    private func sanitized<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch AIServiceError.httpError(let code, _) { throw AIServiceError.requestFailed("Live AI request failed with HTTP \(code); response body withheld to protect credentials.") }
        catch AIServiceError.unparsableResponse { throw AIServiceError.requestFailed("Live AI response failed the structured-output contract; raw response withheld.") }
    }
}

private final class LiveFixtureBundle {}
