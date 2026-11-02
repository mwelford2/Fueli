import Foundation
import Testing
@testable import Fueli

struct MealLookupTests {
    static func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: MealLookupFixtureBundle.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func realUSDASearchResponsesDecode() throws {
        for name in ["bagel", "cream-cheese"] {
            let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self, from: Self.fixture(name))
            #expect(!response.foods.isEmpty)
        }
    }

    @Test func bagelSingularAndPluralMatch() throws {
        let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self, from: Self.fixture("bagel"))
        #expect(!USDAapiCaller.rankedMatches(foods: response.foods, query: "bagels").isEmpty)
        let food = USDAapiCaller.FDCFood(fdcId: 1, description: "Bagels, plain", gtinUpc: nil, dataType: "SR Legacy", nutrients: nil)
        #expect(try USDAapiCaller.matchingFood(foods: [food], query: "bagel").fdcId == 1)
    }

    static func component(_ name: String, grams: Double) -> Component {
        Component(label: name, fdcQuery: name, fallbackQueries: [],
            preferredDataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"], brand: nil,
            quantity: Quantity(amount: grams, unit: "g"), estimatedGrams: grams,
            preparation: nil, measureBasis: .as_packaged, negligible: false, confidence: 0.5)
    }

    static func client(_ protocolType: URLProtocol.Type = MealLookupProtocol.self) -> USDAapiCaller {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [protocolType]
        return USDAapiCaller(apiKey: "fixture-key", session: URLSession(configuration: config))
    }

    @Test func everythingBagelRequiresExplicitApproximationChoice() async throws {
        let component = Self.component("Everything bagel", grams: 105)
        let response = try JSONDecoder().decode(USDAapiCaller.FDCSearchResponse.self, from: Self.fixture("bagel"))
        #expect(USDAapiCaller.rankedMatches(foods: response.foods, query: component.label).isEmpty)
        do {
            _ = try await Self.client().resolveFood(for: component)
            Issue.record("A plain bagel must not be silently treated as an everything bagel")
        } catch AIServiceError.ambiguousFood(let unresolved, let alternatives) {
            #expect(unresolved.label == "Everything bagel")
            #expect(alternatives.map(\.description) == ["Bagel"])
        }
    }

    @Test func correctedWeightsAndExplicitChoiceProduceUSDAIngredientTotals() async throws {
        let bagel = Self.component("Everything bagel", grams: 110.5)
        let cream = Self.component("Cream cheese", grams: 28.25)
        let review = NutritionAnalysisResult(dishName: "Everything bagel with cream cheese", matchStrategy: .ingredients,
            composite: nil, components: [bagel, cream], totalEstimatedGrams: 138.75, confidence: 0.5,
            needsConfirmation: false, clarifyingQuestion: nil, assumptions: [])
        let generic = USDAapiCaller.FDCFood(fdcId: 2707684, description: "Bagel", gtinUpc: nil,
            dataType: "Survey (FNDDS)", nutrients: nil)
        let facts = try await Self.client().analyzeFood(result: review, imageBase64: nil,
            selections: [USDAapiCaller.identity(for: bagel): generic])
        let a = try JSONDecoder().decode(USDAapiCaller.FoodDetail.self, from: Self.fixture("bagel-detail")).coreValues()
        let b = try JSONDecoder().decode(USDAapiCaller.FoodDetail.self, from: Self.fixture("cream-cheese-sr-detail")).coreValues()
        let expected = try #require(a[1008]) * 1.105 + (try #require(b[1008])) * 0.2825
        #expect(abs(facts.caloriesValue - expected) < 0.000001)
        #expect(facts.gramsPerServing == 138.75)
        #expect(facts.ingredients?.count == 2)
        #expect(facts.ingredients?.map(\.sourceRecordID) == ["USDA:2707684", "USDA:173418"])
        #expect(facts.ingredients?.first?.gramsPerServing == 110.5)
    }

    @Test func creamCheeseFallsBackFromIncompleteFoundationRecord() async throws {
        let detail = try JSONDecoder().decode(USDAapiCaller.FoodDetail.self, from: Self.fixture("cream-cheese-detail"))
        #expect(try detail.coreValues()[1079] == nil)
        let food = try await Self.client().resolveFood(for: Self.component("Cream cheese", grams: 28))
        #expect(food.fdcId == 173418)
    }

    @Test func queryFallbackRunsButUnrelatedFoodsAreRejected() async throws {
        var cream = Self.component("Cream cheese", grams: 28)
        cream.fdcQuery = "overly specific query"
        cream.fallbackQueries = ["Cream cheese"]
        #expect(try await Self.client().resolveFood(for: cream).fdcId == 173418)
        do {
            _ = try await Self.client().resolveFood(for: Self.component("Chicken breast", grams: 100))
            Issue.record("Unrelated records must not be selected")
        } catch {
            #expect(error.localizedDescription.contains("Chicken breast"))
            #expect(error.localizedDescription.contains("search completed"))
        }
    }

    @Test func preparationMismatchRequiresReview() throws {
        var component = Self.component("Bagel", grams: 100)
        component.preparation = "baked"
        component.measureBasis = .cooked
        let food = USDAapiCaller.FDCFood(fdcId: 1, description: "Bagels, plain", gtinUpc: nil, dataType: "SR Legacy", nutrients: nil)
        #expect(USDAapiCaller.rankedMatches(foods: [food], query: USDAapiCaller.resolutionQuery(for: component)).isEmpty)
        #expect(USDAapiCaller.reviewAlternatives(foods: [food], component: component).count == 1)
    }

    @Test(arguments: [400, 403, 429]) func rejectedSearchIsNotReportedAsNoMatch(_ status: Int) async throws {
        var component = Self.component("Cream cheese", grams: 28)
        component.fdcQuery = "status-\(status)"
        do {
            _ = try await Self.client().resolveFood(for: component)
            Issue.record("Expected rejection")
        } catch {
            #expect(!error.localizedDescription.contains("No suitable"))
            #expect(error.localizedDescription.contains(status == 429 ? "rate limit" : "HTTP \(status)"))
        }
    }

    @Test func malformedSearchResponseDoesNotBecomeEmptyResults() async throws {
        do {
            _ = try await Self.client().search(query: "malformed")
            Issue.record("Expected decoding error")
        } catch { #expect(error is DecodingError) }
    }

    @Test func offlineSearchDoesNotBecomeEmptyResults() async throws {
        do {
            _ = try await Self.client().search(query: "offline")
            Issue.record("Expected network error")
        } catch {
            #expect(error.localizedDescription.contains("unavailable"))
            #expect(!error.localizedDescription.contains("No suitable"))
        }
    }

    @Test func missingKeyExplainsConfigurationInsteadOfNoResults() async throws {
        do {
            _ = try await USDAapiCaller(apiKey: "").search(query: "cream cheese")
            Issue.record("Expected configuration error")
        } catch { #expect(error.localizedDescription.contains("Settings → Food Database")) }
    }

    @MainActor
    @Test func retryAndCandidateChoiceReusePlanButIngredientEditsReplan() async throws {
        let review = try PhotoMealDescription(dishName: "Everything bagel with cream cheese", observedFacts: [],
            estimates: [], unknowns: [], items: [.init(name: "Everything bagel", estimatedGrams: 105,
                preparation: "", measureBasis: .as_packaged)], clarifyingQuestion: nil).reviewResult()
        var plans = 0
        var resolutions = 0
        let candidate = USDAapiCaller.FDCFood(fdcId: 2707684, description: "Bagel", gtinUpc: nil,
            dataType: "Survey (FNDDS)", nutrients: nil)
        let coordinator = MealAnalysisCoordinator(planner: { result in
            plans += 1
            return result
        }, resolver: { result, selections in
            resolutions += 1
            if resolutions == 1 { throw URLError(.notConnectedToInternet) }
            if selections.isEmpty { throw AIServiceError.ambiguousFood(result.components[0], [candidate]) }
            return NutritionFacts(name: result.dishName, calories: 264, proteinG: 10.6, carbsG: 52.4,
                fatG: 1.32, fiberG: 1.6, servingDescription: "100 g")
        })
        func finishTask() async throws {
            for _ in 0..<100 {
                if !coordinator.isBusy { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            Issue.record("Coordinator did not finish its fixture task")
        }
        coordinator.reviewedDecomposition = review
        coordinator.continueLookup()
        try await finishTask()
        guard case .failed(_, .usdaLookup) = coordinator.phase else { Issue.record("Expected network failure"); return }
        coordinator.retry()
        try await finishTask()
        #expect(plans == 1)
        guard case .choosingMatch(let component, _) = coordinator.phase else { Issue.record("Expected review"); return }
        coordinator.chooseFood(candidate, for: component)
        try await finishTask()
        #expect(plans == 1)
        guard case .done = coordinator.phase else { Issue.record("Expected nutrition confirmation"); return }
        coordinator.returnToIngredientReview()
        coordinator.editComponent(at: 0) { $0.estimatedGrams = 120 }
        coordinator.continueLookup()
        try await finishTask()
        #expect(plans == 2)
        guard case .choosingMatch = coordinator.phase else { Issue.record("An edit must clear the earlier selection"); return }
        #expect(coordinator.reviewedComponent(at: 0)?.estimatedGrams == 120)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUELI_LIVE_USDA_TESTS"] == "1"))
    func optionalLiveBagelAndCreamCheeseLookup() async throws {
        let client = try ReleaseLiveTests.usdaClient()
        let cream = try await client.resolveFood(for: Self.component("Cream cheese", grams: 28))
        #expect(cream.description.lowercased().contains("cream"))
        let bagel = Self.component("Everything bagel", grams: 105)
        do {
            _ = try await client.resolveFood(for: bagel)
            Issue.record("Generic record requires review")
        } catch AIServiceError.ambiguousFood(_, let candidates) {
            #expect(candidates.contains { $0.description == "Bagel" })
        }
    }
}

private final class MealLookupFixtureBundle {}

private final class MealLookupProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            let name: String
            var status = 200
            if url.path.hasSuffix("/foods/search") {
                #expect(request.httpMethod == "POST")
                let data: Data
                if let body = request.httpBody { data = body }
                else {
                    let stream = try #require(request.httpBodyStream)
                    stream.open(); defer { stream.close() }
                    var body = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                    data = body
                }
                let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(payload["pageSize"] as? Int == 50)
                #expect(payload["dataType"] as? [String] == ["Foundation", "SR Legacy", "Survey (FNDDS)"] || payload["dataType"] as? [String] == ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"])
                let query = try #require(payload["query"] as? String).lowercased()
                if query == "offline" { throw URLError(.notConnectedToInternet) }
                if query.hasPrefix("status-") { status = Int(query.dropFirst(7)) ?? 400 }
                name = query.contains("bagel") ? "bagel" : "cream-cheese"
                if query == "overly specific query" || query == "malformed" || status != 200 {
                    let body = Data((query == "malformed" ? "{broken" : "{\"foods\":[]}").utf8)
                    finish(url: url, status: status, data: body); return
                }
            } else {
                switch url.lastPathComponent {
                case "2707684": name = "bagel-detail"
                case "173418": name = "cream-cheese-sr-detail"
                default: name = "cream-cheese-detail"
                }
            }
            finish(url: url, status: status, data: try MealLookupTests.fixture(name))
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    private func finish(url: URL, status: Int, data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
