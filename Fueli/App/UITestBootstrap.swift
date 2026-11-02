#if DEBUG
import Foundation
import SwiftData
import UIKit

/// Explicit Debug-only, UUID-isolated stores. The real store is never opened or
/// reset by UI tests; Release contains neither this bootstrap nor the HTTP stub.
enum UITestBootstrap {
    static var storeID: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--fueli-ui-testing"), let index = args.firstIndex(of: "--fueli-ui-store"),
              args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
    }
    static var isActive: Bool { storeID != nil }
    static var fixtureNetwork: Bool { isActive && ProcessInfo.processInfo.arguments.contains("--fueli-ui-network-fixtures") }
    static func image(_ variable: String) -> UIImage? {
        guard isActive, let path = ProcessInfo.processInfo.environment[variable] else { return nil }
        return UIImage(contentsOfFile: path)
    }
    @MainActor static func container() throws -> ModelContainer {
        guard let id = storeID else { throw CocoaError(.fileReadInvalidFileName) }
        if fixtureNetwork { URLProtocol.registerClass(UITestHTTPProtocol.self) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FueliUITestIsolation/" + id.uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        let config = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("test.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: [config])
        if try container.mainContext.fetchCount(FetchDescriptor<UserProfile>()) == 0 {
            let onboarding = ProcessInfo.processInfo.arguments.contains("--fueli-ui-onboarding")
            let profile = UserProfile(hasCompletedOnboarding: !onboarding, trainingGoal: onboarding ? .cut : .recomp)
            if !onboarding { profile.manualMaintenanceCalories = 2500 }
            container.mainContext.insert(profile)
            if !onboarding {
                let oats = SavedMeal(name: "QA Oats", calories: 150, proteinG: 10, carbsG: 20, fatG: 3, fiberG: 2.5,
                    servingDescription: "50 g standard serving", timesLogged: 7)
                oats.caloriesExact = 150.125; oats.gramsPerServing = 50; oats.isFavorite = true
                container.mainContext.insert(oats)
                let yogurt = SavedMeal(name: "QA Yogurt", calories: 100, proteinG: 12, carbsG: 8, fatG: 2, servingDescription: "100 g")
                yogurt.gramsPerServing = 100; container.mainContext.insert(yogurt)
            }
            try container.mainContext.save()
        }
        return container
    }
}

private final class UITestHTTPProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { UITestBootstrap.fixtureNetwork }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if ProcessInfo.processInfo.arguments.contains("--fueli-ui-network-offline") {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let url = request.url!
        var object: Any = [:]
        var status = ProcessInfo.processInfo.arguments.contains("--fueli-ui-network-error") ? 403 : 200
        do {
            if url.host == "fixture.fueli.invalid" {
                let body: Data
                if let data = request.httpBody { body = data }
                else {
                    var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                    if let stream = request.httpBodyStream {
                        stream.open(); defer { stream.close() }
                        while stream.hasBytesAvailable {
                            let count = stream.read(&buffer, maxLength: buffer.count)
                            guard count > 0 else { break }; data.append(contentsOf: buffer.prefix(count))
                        }
                    }
                    body = data
                }
                let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
                let format = payload["response_format"] as? [String: Any]
                let schema = format?["json_schema"] as? [String: Any]
                let encoded: Data
                if schema?["name"] as? String == MealOutputContract.description.name {
                    encoded = try JSONEncoder().encode(PhotoMealDescription(dishName: "QA Banana", observedFacts: ["One banana"],
                        estimates: ["120 g"], unknowns: ["Weight is an estimate"], items: [.init(name: "banana", estimatedGrams: 120,
                        preparation: "unprepared", measureBasis: .as_packaged)], clarifyingQuestion: nil))
                } else { encoded = try JSONEncoder().encode(ManualMealDescription.parse("120 g banana")) }
                object = ["choices": [["message": ["content": String(decoding: encoded, as: UTF8.self)]]]]
            } else if url.host == "api.nal.usda.gov" {
                if url.path.hasSuffix("/foods/search") {
                    object = ["foods": [["fdcId": 173944, "description": "Bananas, raw", "dataType": "SR Legacy"]]]
                } else {
                    object = ["foodNutrients": [(1008, "kcal", 89.0), (1003, "g", 1.09), (1005, "g", 22.84), (1004, "g", 0.33), (1079, "g", 2.6)]
                        .map { ["nutrient": ["id": $0.0, "unitName": $0.1], "amount": $0.2] as [String: Any] }]
                }
            } else if url.host == "search.openfoodfacts.org" {
                object = ["hits": [["code": "0036000291452", "product_name": "QA Banana Chips", "brands": ["QA"]]], "count": 1]
            } else if url.host == "world.openfoodfacts.org" {
                object = ["product": ["code": "0036000291452", "product_name": "QA Banana Chips", "brands": "QA", "product_quantity_unit": "g",
                    "nutriments": ["energy-kcal_100g": 150.125, "proteins_100g": 10, "carbohydrates-total_100g": 20, "fat_100g": 3, "fiber_100g": 2.5]]]
            } else { status = 404 }
            let data = try JSONSerialization.data(withJSONObject: object)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
