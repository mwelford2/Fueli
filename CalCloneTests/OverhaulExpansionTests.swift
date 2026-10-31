import Foundation
import Testing
import SwiftData
import HealthKit
import UIKit
@testable import CalClone

@MainActor
struct OverhaulExpansionTests {
    @Test func emptyHealthDataIsNotAnAuthorizationFailure() {
        #expect(HealthKitService.isEmptyHealthResult(NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)))
        #expect(!HealthKitService.isEmptyHealthResult(NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)))
    }
    @Test func receiptFixturesStayUnconfirmed() {
        let item = ReceiptParser.parse("CHK BRST BNLS 1.5 LB  8.99", confidence: 0.6)
        #expect(item.name.contains("chicken breast boneless"))
        #expect(!item.name.contains("8.99"))
        #expect(!item.name.contains("1.5"))
        #expect(!item.imported)
        for line in ["SUBTOTAL 12.99", "TAX 0.55", "COUPON -1.00", "VISA 12.54", "TOTAL 12.54"] {
            #expect(ReceiptParser.parse(line, confidence: 0.9).skip)
        }
    }
    @Test func repeatPurchaseRowsAreNotSilentlyDropped() {
        let lines = ["YGRT 1.99", "YGRT 1.99"].map { ReceiptParser.parse($0, confidence: 0.9) }
        #expect(lines[0].id != lines[1].id)
        #expect(lines.allSatisfy { !$0.imported })
    }
    @Test func ingredientScalingKeepsPrecision() throws {
        let ingredient = LibraryIngredient(id: UUID(), name: "Food", servings: 2.5, calories: 150, protein: 10, carbs: 12.25, fat: 1, fiber: 0)
        #expect(try ingredient.nutrition().calories == 375)
        #expect(try ingredient.nutrition().protein == 25)
    }
    @Test func spatialOCRRowReconstruction() {
        let fragments = [ReceiptParser.Fragment(text: "CHK BRST", x: 0.1, y: 0.8, height: 0.03, confidence: 0.9),
                         ReceiptParser.Fragment(text: "8.99", x: 0.8, y: 0.805, height: 0.03, confidence: 0.8),
                         ReceiptParser.Fragment(text: "TAX 0.55", x: 0.1, y: 0.7, height: 0.03, confidence: 0.9)]
        let rows = ReceiptParser.reconstruct(fragments)
        #expect(rows.count == 2)
        #expect(rows[0].name == "chicken breast")
        #expect(rows[1].skip)
    }
    @Test func visionRecognizesSyntheticReceiptOnDevice() async throws {
        let bundle = Bundle(for: ReceiptFixtureBundle.self)
        let url = try #require(bundle.url(forResource: "SyntheticReceipt", withExtension: "png"))
        let image = try #require(UIImage(contentsOfFile: url.path))
        let rows = try await ReceiptParser.recognize(image)
        let fallbackRows = try await ReceiptParser.recognize(image, preferStructured: false)
        #expect(fallbackRows.contains { $0.name.contains("chicken breast") })
        #expect(fallbackRows.filter { $0.name.contains("yogurt") }.count == 2)
        #expect(rows.contains { $0.name.contains("chicken breast") })
        #expect(rows.filter { $0.name.contains("yogurt") }.count == 2)
        #expect(rows.filter(\.skip).count >= 5)
        #expect(rows.allSatisfy { !$0.imported })
    }
    @Test func backupRoundTripAndRepeatImport() throws {
        let schema = Schema([SavedMeal.self, FoodLog.self])
        func container() throws -> ModelContainer { try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)) }
        let source = try container()
        let food = SavedMeal(name: "Test food", calories: 150, proteinG: 10, carbsG: 12.25, fatG: 2)
        food.ingredientData = try JSONEncoder().encode([LibraryIngredient(id: UUID(), preparation: "grilled", measureBasis: .cooked, quantityIsEstimated: true, name: "Ingredient", servings: 0.5, calories: 300, protein: 20, carbs: 24.5, fat: 4, fiber: 0)])
        source.mainContext.insert(food)
        let log = FoodLog(name: "Test food", calories: 75, proteinG: 5, carbsG: 6.125, fatG: 1, servings: 0.5, source: .savedMeal, notes: "Snapshot")
        log.savedFoodID = food.id
        source.mainContext.insert(log); try source.mainContext.save()
        let backup = try LibraryBackup.capture(source.mainContext, images: false)
        let encoded = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(LibraryBackup.self, from: encoded)
        let target = try container()
        #expect(try decoded.restore(target.mainContext) == 2)
        #expect(try decoded.restore(target.mainContext) == 0)
        let restored = try #require(target.mainContext.fetch(FetchDescriptor<FoodLog>()).first)
        #expect(restored.servings == 0.5)
        #expect(restored.savedFoodID == food.id)
        #expect(restored.notes == "Snapshot")
        let restoredFoods = try target.mainContext.fetch(FetchDescriptor<SavedMeal>())
        let ingredientData = try #require(restoredFoods.first?.ingredientData)
        let restoredIngredients = try JSONDecoder().decode([LibraryIngredient].self, from: ingredientData)
        #expect(restoredIngredients.first?.preparation == "grilled")
        #expect(restoredIngredients.first?.measureBasis == .cooked)
        #expect(restoredIngredients.first?.quantityIsEstimated == true)
        food.calories = 999
        #expect(log.calories == 75)
    }
    @Test func barcodeTotalCarbohydratesAndKJ() throws {
        let json = #"{"product":{"code":"0036000291452","product_quantity_unit":"g","product_name":"Test Food","nutriments":{"energy-kj_100g":418.4,"proteins_100g":5.25,"carbohydrates_100g":10,"fat_100g":2,"fiber_100g":3}}}"#
        let decoded = try JSONDecoder().decode(BarcodeLookupService.OFFResponse.self, from: Data(json.utf8))
        let facts = try BarcodeLookupService.normalize(decoded, barcode: "036000291452")
        #expect(facts.calories == 100)
        #expect(facts.carbsG == 13)
        #expect(facts.proteinG == 5.25)
        #expect(facts.barcode == "0036000291452")
    }
    @Test func explicitTotalDoesNotAddFiberTwice() throws {
        let json = #"{"product":{"code":"0036000291452","product_quantity_unit":"g","product_name":"Test","nutriments":{"energy-kcal_100g":100,"proteins_100g":0,"carbohydrates-total_100g":13,"carbohydrates_100g":10,"fat_100g":0,"fiber_100g":3}}}"#
        let decoded = try JSONDecoder().decode(BarcodeLookupService.OFFResponse.self, from: Data(json.utf8))
        #expect(try BarcodeLookupService.normalize(decoded, barcode: "036000291452").carbsG == 13)
        #expect(throws: (any Swift.Error).self) { try BarcodeLookupService.normalize(decoded, barcode: "96385074") }
    }
    @Test func missingBarcodeNutritionRequiresReview() throws {
        let json = #"{"product":{"code":"0036000291452","product_quantity_unit":"g","product_name":"Test","nutriments":{"proteins_100g":0}}}"#
        let decoded = try JSONDecoder().decode(BarcodeLookupService.OFFResponse.self, from: Data(json.utf8))
        #expect(throws: (any Swift.Error).self) { try BarcodeLookupService.normalize(decoded, barcode: "036000291452") }
    }
    @Test func photoDescriptionHasNoInventedNutrition() throws {
        let description = PhotoMealDescription(dishName: "Chicken", observedFacts: ["grilled surface"],
            estimates: ["150 grams"], unknowns: ["oil quantity"], items: [.init(name: "Chicken breast", estimatedGrams: 150,
            preparation: "grilled", measureBasis: .cooked)], clarifyingQuestion: nil)
        let review = try description.reviewResult()
        #expect(review.components[0].estimatedGrams == 150)
        #expect(review.components[0].preparation == "grilled")
        let json = String(decoding: try JSONEncoder().encode(description), as: UTF8.self)
        #expect(!json.contains("calories"))
        #expect(!json.contains("fdc_query"))
    }
    @Test func usdaDetailedUnitsAreNormalized() throws {
        let json = #"{"foodNutrients":[{"nutrient":{"id":1062,"unitName":"kJ"},"amount":418.4},{"nutrient":{"id":1003,"unitName":"g"},"amount":12.25}]}"#
        let detail = try JSONDecoder().decode(USDAapiCaller.FoodDetail.self, from: Data(json.utf8))
        let values = try detail.coreValues()
        #expect(abs((values[1008] ?? 0) - 100) < 0.00001)
        #expect(values[1003] == 12.25)
        #expect(values[1079] == nil)
    }
    @Test func usdaMatcherRejectsUnrelatedAndAmbiguousCandidates() throws {
        let json = #"{"foods":[{"fdcId":1,"description":"Bananas, raw"},{"fdcId":2,"description":"Banana chips"}]}"#
        let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self, from: Data(json.utf8))
        #expect(try USDAapiCaller.matchingFood(foods: response.foods, query: "banana raw").fdcId == 1)
        #expect(throws: (any Swift.Error).self) { try USDAapiCaller.matchingFood(foods: response.foods, query: "chicken breast grilled") }
    }

    @Test func liquidBarcodeDoesNotInventMassConversion() throws {
        let json = #"{"product":{"code":"0036000291452","product_quantity_unit":"ml","product_name":"Test drink","nutriments":{"energy-kcal_100g":20,"proteins_100g":0,"carbohydrates-total_100g":5,"fat_100g":0,"fiber_100g":0}}}"#
        let decoded = try JSONDecoder().decode(BarcodeLookupService.OFFResponse.self, from: Data(json.utf8))
        let facts = try BarcodeLookupService.normalize(decoded, barcode: "036000291452")
        #expect(facts.gramsPerServing == nil)
        #expect(facts.millilitersPerServing == 100)
    }

    @Test func conflictingDatabaseNutritionRequiresReview() {
        let a = NutritionFacts(name: "Source A", calories: 100, proteinG: 5, carbsG: 10, fatG: 3, servingDescription: "100 g", gramsPerServing: 100)
        let b = NutritionFacts(name: "Source B", calories: 300, proteinG: 5, carbsG: 10, fatG: 3, servingDescription: "100 g", gramsPerServing: 100)
        #expect(BarcodeLookupService.materiallyDisagree(a, b))
        #expect(!BarcodeLookupService.materiallyDisagree(a, a))
    }
    @Test func incompatibleBackupIsRejected() throws {
        var backup = LibraryBackup(foods: [], logs: [])
        backup.version = 999
        #expect(throws: (any Swift.Error).self) { try backup.validate() }
    }
    @Test func foundationEnergyUsesOneDocumentedAtwaterValue() throws {
        let json = #"{"foodNutrients":[{"nutrient":{"id":2047,"unitName":"kcal"},"amount":102.75},{"nutrient":{"id":2048,"unitName":"kcal"},"amount":99.125}]}"#
        let detail = try JSONDecoder().decode(USDAapiCaller.FoodDetail.self, from: Data(json.utf8))
        #expect(try detail.coreValues()[1008] == 99.125)
    }
    @Test func fractionalCaloriesSurviveAggregationAndBackup() throws {
        let schema = Schema([SavedMeal.self, FoodLog.self])
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let food = SavedMeal(name: "Precise serving", calories: 101, proteinG: 1.125, carbsG: 2.25, fatG: 3.5)
        food.caloriesExact = 100.625
        food.millilitersPerServing = 250
        source.mainContext.insert(food)
        let ingredient = LibraryIngredient(id: UUID(), name: food.name, servings: 0.25, calories: food.caloriesValue, protein: food.proteinG, carbs: food.carbsG, fat: food.fatG, fiber: 0)
        #expect(try ingredient.nutrition().calories == 25.15625)
        let log = food.makeLog(mealType: .lunch)
        source.mainContext.insert(log)
        try source.mainContext.save()
        let backup = try LibraryBackup.capture(source.mainContext, images: false)
        let decoded = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(backup))
        let target = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(try decoded.restore(target.mainContext) == 2)
        let foods = try target.mainContext.fetch(FetchDescriptor<SavedMeal>())
        #expect(foods.first?.caloriesValue == 100.625)
        #expect(foods.first?.millilitersPerServing == 250)
        let logs = try target.mainContext.fetch(FetchDescriptor<FoodLog>())
        #expect(logs.first?.caloriesValue == 100.625)
    }
    @Test func correctedPreparationIsRequiredByCandidateMatching() throws {
        let description = PhotoMealDescription(dishName: "Chicken", observedFacts: [], estimates: [], unknowns: [], items: [.init(name: "Chicken breast", estimatedGrams: 150, preparation: "grilled skinless", measureBasis: .cooked)], clarifyingQuestion: nil)
        let review = try description.reviewResult()
        let json = #"{"foods":[{"fdcId":1,"description":"Chicken breast cooked fried skinless","dataType":"Foundation"},{"fdcId":2,"description":"Chicken breast cooked grilled skinless","dataType":"SR Legacy"}]}"#
        let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self, from: Data(json.utf8))
        let matches = USDAapiCaller.rankedMatches(foods: response.foods, query: USDAapiCaller.resolutionQuery(for: review.components[0]))
        #expect(matches.map(\.fdcId) == [2])
        let coordinator = MealAnalysisCoordinator()
        coordinator.reviewedDecomposition = review
        coordinator.editComponent(at: 0) { $0.estimatedGrams = 175.5; $0.preparation = "roasted" }
        #expect(coordinator.reviewedComponent(at: 0)?.estimatedGrams == 175.5)
        #expect(coordinator.reviewedComponent(at: 0)?.preparation == "roasted")
        coordinator.addComponent()
        #expect(!coordinator.canContinueLookup)
        coordinator.removeComponent(at: 1)
        #expect(coordinator.canContinueLookup)
        coordinator.removeComponent(at: 99)
        #expect(coordinator.reviewedDecomposition?.components.count == 1)
    }
    @Test func paddedDatabaseGTINsMatchWithoutGuessingUPCE() {
        #expect(BarcodeLookupService.sameGTIN("00000096385074", "96385074"))
        #expect(BarcodeLookupService.sameGTIN("00036000291452", "036000291452"))
        #expect(!BarcodeLookupService.sameGTIN("00000096385075", "96385074"))
        #expect(!BarcodeLookupService.sameGTIN("invalid", "also invalid"))
    }

    @Test func providerSchemasForbidExtraPropertiesAndNutritionInPlan() throws {
        for contract in [MealOutputContract.description, .lookupPlan] {
            let schema = contract.schema
            #expect(schema["additionalProperties"] as? Bool == false)
            let properties = try #require(schema["properties"] as? [String: Any])
            let required = try #require(schema["required"] as? [String])
            #expect(Set(required) == Set(properties.keys))
            let json = String(decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
            #expect(!json.contains("calories"))
            #expect(!json.contains("protein"))
        }
        #expect(AINutritionService.rejectsStructuredOutput(status: 400, data: Data("response_format json_schema is not supported".utf8), anthropic: false))
        #expect(AINutritionService.rejectsStructuredOutput(status: 400, data: Data("Unknown parameter output_config".utf8), anthropic: true))
        #expect(!AINutritionService.rejectsStructuredOutput(status: 429, data: Data("response_format unsupported".utf8), anthropic: false))
        #expect(!AINutritionService.rejectsStructuredOutput(status: 400, data: Data("Invalid schema response_format: missing required properties".utf8), anthropic: false))
    }
    @Test func barcodeRateLimitHasCooldown() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RateLimitedProductProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = BarcodeLookupService(session: session)
        do { _ = try await service.lookup(barcode: "036000291452"); Issue.record("Expected rate limit") }
        catch { #expect(error.localizedDescription.contains("Retry after 120")) }
        do { _ = try await service.lookup(barcode: "036000291452"); Issue.record("Expected cooldown") }
        catch { #expect(error.localizedDescription.contains("Wait before retrying")) }
    }
    @Test func malformedProductJSONDoesNotBecomeACompleteFood() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MalformedProductProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = BarcodeLookupService(session: session)
        do { _ = try await service.lookup(barcode: "036000291452"); Issue.record("Malformed JSON must fail") }
        catch { #expect(error is DecodingError) }
    }

    @Test func personalUSDAKeyOverridesOnlyDevelopmentBundleConfiguration() {
        #expect(USDAapiCaller.resolveAPIKey(userKey: " personal-test-key ", bundledKey: "development-test-key") == "personal-test-key")
        #expect(USDAapiCaller.resolveAPIKey(userKey: nil, bundledKey: "development-test-key") == "development-test-key")
        #expect(USDAapiCaller.resolveAPIKey(userKey: "", bundledKey: "") == "")
        #expect(USDAapiCaller.resolveAPIKey(userKey: nil, bundledKey: "$(USDA_API_KEY)") == "")
        #expect(USDAapiCaller.resolveAPIKey(userKey: "invalid key", bundledKey: nil) == "")
        #expect(USDAapiCaller(apiKey: "injected-test-key").APIKey == "injected-test-key")
    }

    @Test func personalKeychainStorageUpdatesAndDeletesDedicatedFixture() throws {
        let account = "fueli-keychain-fixture-" + UUID().uuidString
        defer { try? KeychainStore.deleteChecked(account: account) }
        try KeychainStore.saveChecked("fixture-one", account: account)
        #expect(KeychainStore.read(account: account) == "fixture-one")
        try KeychainStore.saveChecked("fixture-two", account: account)
        #expect(KeychainStore.read(account: account) == "fixture-two")
        try KeychainStore.deleteChecked(account: account)
        #expect(KeychainStore.read(account: account) == nil)
    }

}

private class ReceiptFixtureBundle: NSObject {}

private final class RateLimitedProductProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class MalformedProductProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{malformed".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
