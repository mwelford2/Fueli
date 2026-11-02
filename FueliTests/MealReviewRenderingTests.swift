import XCTest
import SwiftUI
@testable import Fueli

/// Captures the actual shared SwiftUI review for visual inspection in xcresult.
/// Uses synthetic inputs and does not read or change the persistent food library.
@MainActor
final class MealReviewRenderingTests: XCTestCase {
    func testOpenFoodFactsReviewAndProductConfirmationSnapshots() async throws {
        let product = FoodProductCandidate(code: "0036000291452", product_name: "Cream cheese", brands: ["Synthetic test brand"])
        let coordinator = MealAnalysisCoordinator(
            decomposer: { _, _ in
                try PhotoMealDescription(dishName: "Cream cheese", observedFacts: ["White spread"],
                    estimates: ["28.25 g"], unknowns: ["Brand cannot be established from the photo"],
                    items: [.init(name: "Cream cheese", estimatedGrams: 28.25, preparation: "Spread",
                        measureBasis: .as_packaged)], clarifyingQuestion: nil).reviewResult()
            }, productSearch: { _, _ in FoodProductPage(products: [product], page: 1, hasMore: false) },
            productDetail: { _ in MealDatabaseChoiceTests.reference("Synthetic test brand · Cream cheese") })
        coordinator.start(.init(userText: nil, imageBase64: "synthetic-photo-fixture", kind: .photo))
        try await MealDatabaseChoiceTests.finish(coordinator)
        coordinator.selectDatabase(.openFoodFacts)
        try await attachReview(coordinator, named: "Photo AI description and Open Food Facts choice")
        coordinator.continueLookup()
        try await MealDatabaseChoiceTests.finish(coordinator)
        try await attachReview(coordinator, named: "Explicit packaged product search results")
        coordinator.selectProduct(product, at: 0)
        try await MealDatabaseChoiceTests.finish(coordinator)
        try await attachReview(coordinator, named: "Confirm package and selected gram amount")
        coordinator.confirmProduct()
        guard case .done(let facts) = coordinator.phase else { XCTFail("Expected final confirmation facts"); return }
        XCTAssertEqual(facts.gramsPerServing, 28.25)
    }

    private func attachReview(_ coordinator: MealAnalysisCoordinator, named name: String) async throws {
        let host = UIHostingController(rootView: ScrollView {
            MealAnalysisProgressView(coordinator: coordinator)
        }.padding(.top, 16).preferredColorScheme(.light))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 1050)
        window.rootViewController = host
        host.view.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPopulatedIngredientReviewSnapshot() async throws {
        let coordinator = MealAnalysisCoordinator()
        coordinator.reviewedDecomposition = try PhotoMealDescription(
            dishName: "Everything bagel with cream cheese", observedFacts: [], estimates: [], unknowns: [],
            items: [
                .init(name: "Everything bagel", estimatedGrams: 105, preparation: "Toasted", measureBasis: .cooked),
                .init(name: "Cream cheese", estimatedGrams: 28, preparation: "Spread", measureBasis: .as_packaged)
            ], clarifyingQuestion: nil).reviewResult()
        coordinator.returnToIngredientReview()
        let host = UIHostingController(rootView: ScrollView {
            MealAnalysisProgressView(coordinator: coordinator)
        }.padding(.top, 20).preferredColorScheme(.light))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        host.view.backgroundColor = .systemBackground
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertGreaterThan(host.view.bounds.width, 0)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Populated ingredient weights with persistent gram labels"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
