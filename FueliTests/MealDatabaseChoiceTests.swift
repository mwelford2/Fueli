import Foundation
import Testing
import SwiftData
@testable import Fueli

struct MealDatabaseChoiceTests {
    @Test func queryCleanupKeepsIdentityAndRemovesAmountsAndQuerySyntax() throws {
        var component = MealLookupTests.component("28 g cream cheese", grams: 28)
        #expect(try IngredientSearchText.query(for: component) == "cream cheese")
        component.label = "2% milk"
        #expect(try IngredientSearchText.query(for: component) == "2 percent milk")
        component.label = "Chicken breast (150 grams)"
        component.preparation = "grilled skinless"
        component.brand = "Brand's"
        #expect(try IngredientSearchText.query(for: component) == "brand s chicken breast grilled skinless")
        #expect(IngredientSearchText.clean("cream:cheese +brands:* (OR) \"milk\"") == "cream cheese brands or milk")
    }

    @Test func deterministicSplitDoesNotInventHouseholdWeightsOrSplitCompoundNames() throws {
        let meal = try ManualMealDescription.parse("105g everything bagel with 28 g cream cheese; mac and cheese\n2 eggs")
        #expect(meal.components.map(\.label) == ["everything bagel", "cream cheese", "mac and cheese", "2 eggs"])
        #expect(meal.components.map(\.estimatedGrams) == [105, 28, 0, 0])
        let ounce = try ManualMealDescription.parse("1 oz cheese; 0.5 lb chicken; 0.15 kg rice")
        #expect(ounce.components[0].estimatedGrams == 28.349523125)
        #expect(ounce.components[1].estimatedGrams == 226.796185)
        #expect(ounce.components[2].estimatedGrams == 150)
        #expect(throws: (any Swift.Error).self) { try ManualMealDescription.parse(" ") }
        for invalid in ["-28 g cheese", "−28 g cheese", "0 g cheese"] {
            #expect(throws: (any Swift.Error).self) { try ManualMealDescription.parse(invalid) }
        }
        // Commas are ambiguous decimal/thousands separators; require explicit review.
        #expect(try ManualMealDescription.parse("28,25 g cheese").components.first?.estimatedGrams == 0)
        #expect(try ManualMealDescription.parse("150 g cooked chicken").components.first?.measureBasis == .cooked)
        var raw = try ManualMealDescription.parse("150 g chicken breast")
        raw.components[0].measureBasis = .raw
        raw.components[0].preparation = "skinless"
        #expect(ManualMealDescription.lookupPlan(from: raw).components[0].fdcQuery == "chicken breast raw skinless")
    }

    @Test func brandCorrectionCannotSilentlyResolveToGenericUSDAFood() throws {
        var component = MealLookupTests.component("Cream cheese", grams: 28)
        component.brand = "Selected Brand"
        let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self,
            from: Data(#"{"foods":[{"fdcId":1,"description":"Cheese, cream","dataType":"Foundation"},{"fdcId":2,"description":"Cream cheese","dataType":"Branded","brandName":"Selected Brand"}]}"#.utf8))
        let matches = USDAapiCaller.rankedMatches(foods: response.foods, query: USDAapiCaller.resolutionQuery(for: component))
        #expect(matches.map(\.fdcId) == [2])
    }

    static func reference(_ name: String = "Test package", code: String = "0036000291452") -> NutritionFacts {
        NutritionFacts(name: name, calories: 150, proteinG: 10, carbsG: 12.25, fatG: 3.5, fiberG: 0,
            servingDescription: "100 g · Open Food Facts", barcode: code, sourceRecordID: "OFF:" + code,
            gramsPerServing: 100, caloriesExact: 150.125)
    }

    @Test func packageCalculationPreservesCorrectedWeightsAndSources() throws {
        var review = try ManualMealDescription.parse("250 g bagel; 50 g cream cheese")
        review.components[0].estimatedGrams = 125.5
        let facts = try MealRecordCalculation.assemble(review, references: [0: Self.reference(), 1: Self.reference("Cheese", code: "96385074")])
        #expect(facts.gramsPerServing == 175.5)
        #expect(abs(facts.caloriesValue - 150.125 * 1.755) < 0.0000001)
        #expect(facts.ingredients?.map(\.sourceRecordID) == ["OFF:0036000291452", "OFF:96385074"])
        #expect(facts.ingredients?.first?.servings == 1.255)
        #expect(facts.ingredients?.first?.calories == 150.125)
        #expect(throws: (any Swift.Error).self) { try MealRecordCalculation.assemble(review, references: [0: Self.reference()]) }
    }

    @Test func cookedWeightVolumeAndInvalidQuantitiesCannotBeSilentlyConverted() throws {
        var component = MealLookupTests.component("Cheese", grams: 28)
        component.measureBasis = .cooked
        #expect(throws: (any Swift.Error).self) { try MealRecordCalculation.ingredient(component: component, reference: Self.reference()) }
        component.measureBasis = .as_packaged
        var volume = Self.reference(); volume.gramsPerServing = nil; volume.millilitersPerServing = 100
        #expect(throws: (any Swift.Error).self) { try MealRecordCalculation.ingredient(component: component, reference: volume) }
        component.estimatedGrams = .infinity
        #expect(throws: (any Swift.Error).self) { try MealRecordCalculation.ingredient(component: component, reference: Self.reference()) }
    }

    @MainActor static func finish(_ coordinator: MealAnalysisCoordinator) async throws {
        for _ in 0..<100 {
            if !coordinator.isBusy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Fixture operation did not complete")
    }

    @MainActor @Test func photoStopsForEditableDescriptionBeforeSelectedDatabaseAndDoesNotReplanForOFF() async throws {
        var descriptions = 0, plans = 0, usdaCalls = 0, searches = 0, details = 0
        let product = FoodProductCandidate(code: "0036000291452", product_name: "Cream cheese", brands: ["Test brand"])
        let coordinator = MealAnalysisCoordinator(planner: { value in plans += 1; return value },
            resolver: { _, _ in usdaCalls += 1; return Self.reference() },
            decomposer: { input, _ in
                descriptions += 1
                #expect(input.imageBase64 == "synthetic-test-image")
                return try PhotoMealDescription(dishName: "Bagel with cream cheese", observedFacts: ["two foods"],
                    estimates: ["28 g cream cheese"], unknowns: ["brand"], items: [.init(name: "Cream cheese",
                        estimatedGrams: 28, preparation: "spread", measureBasis: .as_packaged)], clarifyingQuestion: nil).reviewResult()
            }, productSearch: { query, page in
                searches += 1; #expect(query == "cream cheese"); #expect(page == 1)
                return FoodProductPage(products: [product], page: 1, hasMore: false)
            }, productDetail: { code in details += 1; #expect(code == product.code); return Self.reference() })
        coordinator.start(.init(userText: nil, imageBase64: "synthetic-test-image", kind: .photo))
        try await Self.finish(coordinator)
        #expect(coordinator.phase == .reviewing)
        #expect(searches == 0 && usdaCalls == 0)
        #expect(coordinator.reviewedDecomposition?.dishName == "Bagel with cream cheese")
        coordinator.editComponent(at: 0) { $0.estimatedGrams = 35.5 }
        coordinator.selectDatabase(.openFoodFacts)
        coordinator.continueLookup()
        try await Self.finish(coordinator)
        guard case .choosingProducts = coordinator.phase else { Issue.record("Expected explicit product choice"); return }
        #expect(details == 0)
        coordinator.selectProduct(product, at: 0)
        try await Self.finish(coordinator)
        guard case .reviewingProduct = coordinator.phase else { Issue.record("Expected label confirmation"); return }
        coordinator.confirmProduct()
        guard case .done(let facts) = coordinator.phase else { Issue.record("Expected calculated totals"); return }
        #expect(abs(facts.caloriesValue - 150.125 * 0.355) < 0.000001)
        #expect(descriptions == 1 && plans == 0 && usdaCalls == 0 && searches == 1 && details == 1)
    }

    @MainActor @Test func manualEntryUsesNeitherAIStageAndCanSwitchDatabasesWithoutLosingEdits() async throws {
        var plans = 0, aiCalls = 0, usdaCalls = 0
        let coordinator = MealAnalysisCoordinator(planner: { value in plans += 1; return value },
            resolver: { result, _ in
                usdaCalls += 1
                #expect(result.components[0].estimatedGrams == 120)
                return Self.reference()
            }, decomposer: { _, _ in aiCalls += 1; throw NutritionValidationError.incomplete },
            productSearch: { _, _ in FoodProductPage(products: [], page: 1, hasMore: false) })
        coordinator.selectDatabase(.openFoodFacts)
        coordinator.startWithoutAI("bagel with cream cheese")
        #expect(!coordinator.canContinueLookup)
        coordinator.editComponent(at: 0) { $0.estimatedGrams = 120 }
        coordinator.editComponent(at: 1) { $0.estimatedGrams = 30 }
        coordinator.continueLookup()
        try await Self.finish(coordinator)
        guard case .choosingProducts(_, _, let page) = coordinator.phase else { Issue.record("Expected empty results review"); return }
        #expect(page.products.isEmpty)
        coordinator.selectDatabase(.usda)
        #expect(coordinator.reviewedComponent(at: 0)?.estimatedGrams == 120)
        coordinator.continueLookup()
        try await Self.finish(coordinator)
        #expect(plans == 0 && aiCalls == 0 && usdaCalls == 1)
    }

    @MainActor @Test func offlineProductRetryRetainsDescriptionAndDoesNotCallAI() async throws {
        var searches = 0
        let coordinator = MealAnalysisCoordinator(productSearch: { _, _ in
            searches += 1
            if searches == 1 { throw URLError(.notConnectedToInternet) }
            return FoodProductPage(products: [], page: 1, hasMore: false)
        })
        coordinator.selectDatabase(.openFoodFacts)
        coordinator.startWithoutAI("28 g cream cheese")
        coordinator.continueLookup()
        try await Self.finish(coordinator)
        guard case .failed(_, .openFoodFactsLookup) = coordinator.phase else { Issue.record("Expected retryable failure"); return }
        coordinator.retry()
        try await Self.finish(coordinator)
        #expect(searches == 2)
        #expect(coordinator.reviewedComponent(at: 0)?.estimatedGrams == 28)
        guard case .choosingProducts = coordinator.phase else { Issue.record("Expected search review"); return }
    }

    @MainActor @Test func cancelAndChangeDatabaseIgnoresStaleSearchCompletion() async throws {
        let coordinator = MealAnalysisCoordinator(productSearch: { _, _ in
            try? await Task.sleep(for: .milliseconds(100))
            return FoodProductPage(products: [], page: 1, hasMore: false)
        })
        coordinator.selectDatabase(.openFoodFacts)
        coordinator.startWithoutAI("28 g cream cheese")
        coordinator.continueLookup()
        await Task.yield()
        coordinator.selectDatabase(.usda)
        try await Task.sleep(for: .milliseconds(150))
        #expect(coordinator.database == .usda)
        #expect(coordinator.phase == .reviewing)
        coordinator.startWithoutAI("-28g cheese")
        #expect(coordinator.enteredWithoutAI)
        coordinator.resetReview()
        #expect(coordinator.phase == .idle && coordinator.reviewedDecomposition == nil)
    }

    @MainActor @Test func selectedProductRecipeAndHistoricalSourcesSurviveBackup() throws {
        let review = try ManualMealDescription.parse("28.25 g cream cheese")
        let facts = try MealRecordCalculation.assemble(review, references: [0: Self.reference()])
        let schema = Schema([SavedMeal.self, FoodLog.self])
        let source = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let food = SavedMeal(name: facts.name, calories: facts.calories, proteinG: facts.proteinG,
            carbsG: facts.carbsG, fatG: facts.fatG, fiberG: facts.fiberG)
        food.caloriesExact = facts.caloriesValue
        food.ingredientData = try JSONEncoder().encode(facts.ingredients)
        source.mainContext.insert(food)
        let log = food.makeLog(mealType: .breakfast)
        log.recipeIngredientsData = food.ingredientData
        source.mainContext.insert(log); try source.mainContext.save()
        let backup = try LibraryBackup.capture(source.mainContext, images: false)
        let decoded = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(backup))
        let target = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(try decoded.restore(target.mainContext) == 2)
        #expect(try decoded.restore(target.mainContext) == 0)
        let restored = try #require(target.mainContext.fetch(FetchDescriptor<FoodLog>()).first)
        #expect(restored.caloriesValue == facts.caloriesValue)
        let ingredients = try JSONDecoder().decode([LibraryIngredient].self, from: #require(restored.recipeIngredientsData))
        #expect(ingredients.first?.sourceRecordID == "OFF:0036000291452")
        #expect(ingredients.first?.servings == 0.2825)
    }
}
