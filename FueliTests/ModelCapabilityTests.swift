import Foundation
import Testing
@testable import Fueli

struct ModelCapabilityTests {
    private func models(_ json: String) -> [AINutritionService.DiscoveredModel] {
        AINutritionService.parseModelList(Data(json.utf8))
    }

    @Test func gemmaSparseVisionMetadataUsesGoogleCard() throws {
        let partial = try #require(models(#"{"data":[{"id":"gemma-4-31b-it","supports_vision":true}]}"#).first)
        #expect(!partial.hasCompleteCapabilityMetadata)
        let resolved = AINutritionService.resolveCapabilities(partial, database: nil)
        #expect(resolved.supportsTextAndImage)
        #expect(resolved.capabilitySource?.contains("ai.google.dev") == true)
    }

    @Test func namespacedGemmaAndNoNetworkFallback() throws {
        let entry = try #require(models(#"{"data":[{"id":"google/gemma-4-31b-it"}]}"#).first)
        #expect(AINutritionService.resolveCapabilities(entry, database: nil).supportsTextAndImage)
    }

    @Test func officialCardOverridesIncorrectGatewayFlags() throws {
        let entry = try #require(models(#"{"data":[{"id":"gemma-4-31b-it","supports_vision":false}]}"#).first)
        let resolved = AINutritionService.resolveCapabilities(entry, database: nil)
        #expect(resolved.capabilities?.contains(.text) == true)
        #expect(resolved.capabilities?.contains(.image) == true)
    }

    @Test func officialCardOverridesStaleGatewayInputList() throws {
        let entry = try #require(models(#"{"data":[{"id":"gemma-4-31b-it","architecture":{"input_modalities":["text"]}}]}"#).first)
        #expect(AINutritionService.resolveCapabilities(entry, database: nil).supportsTextAndImage)
    }

    @Test func unknownPartialFlagsDoNotAssertNoText() throws {
        let entry = try #require(models(#"{"data":[{"id":"unknown-model","supports_vision":true}]}"#).first)
        let resolved = AINutritionService.resolveCapabilities(entry, database: nil)
        #expect(!resolved.hasCompleteCapabilityMetadata)
        #expect(resolved.capabilityLabel.contains("unknown"))
        #expect(!resolved.supportsTextAndImage)
    }

    @Test func liteLLMMissingModeStillResolvesGemma() throws {
        let json = #"{"data":[{"model_name":"gemma-4-31b-it","model_info":{"supports_vision":true}}]}"#
        let entry = try #require(AINutritionService.parseLiteLLMModelInfo(Data(json.utf8)).first)
        #expect(AINutritionService.resolveCapabilities(entry, database: nil).supportsTextAndImage)
    }

    @Test func catalogIsExactAndConservative() throws {
        let json = #"{"a":{"models":{"model":{"modalities":{"input":["text","image"]}}}},"b":{"models":{"model":{"modalities":{"input":["text"]}}}}}"#
        let db = try AINutritionService.ModelsDevDatabase(json: Data(json.utf8))
        #expect(db.capabilities(forModelID: "model") == [.text])
        #expect(db.capabilities(forModelID: "model-20261030") == nil)
        #expect(db.capabilities(forModelID: "unknown") == nil)
    }
    @Test func huggingFaceTaskMetadata() throws {
        let json = Data(#"{"id":"google/gemma-4-31B-it","pipeline_tag":"image-text-to-text"}"#.utf8)
        let decoded = try AINutritionService.capabilitiesFromHuggingFace(json,
            repository: "google/gemma-4-31B-it", modelID: "gemma-4-31b-it")
        let result = try #require(decoded)
        #expect(result.id == "gemma-4-31b-it")
        #expect(result.supportsTextAndImage)
        #expect(result.capabilitySource?.contains("huggingface.co/google/") == true)
    }
    @Test func mismatchedOrUnknownHFMetadataIsRejected() throws {
        let wrong = Data(#"{"id":"other/model","pipeline_tag":"image-text-to-text"}"#.utf8)
        #expect(try AINutritionService.capabilitiesFromHuggingFace(wrong, repository: "google/gemma-4-31B-it", modelID: "gemma") == nil)
        let unknown = Data(#"{"id":"owner/model","pipeline_tag":"unknown"}"#.utf8)
        #expect(try AINutritionService.capabilitiesFromHuggingFace(unknown, repository: "owner/model", modelID: "model") == nil)
    }
    @Test func noFuzzyRepositoryGuessing() {
        #expect(AINutritionService.huggingFaceRepository(for: "gemma-4-31b-it") == "google/gemma-4-31B-it")
        #expect(AINutritionService.huggingFaceRepository(for: "unknown-model") == nil)
        #expect(AINutritionService.huggingFaceRepository(for: "owner/model") == "owner/model")
        #expect(AINutritionService.huggingFaceRepository(for: "owner/../model") == nil)
    }

}
