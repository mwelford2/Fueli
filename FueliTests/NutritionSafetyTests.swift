import Testing
import Foundation
@testable import Fueli

struct NutritionSafetyTests {
    @Test func gtinEquivalence() throws {
        #expect(try RetailBarcode("036000291452").canonical == RetailBarcode("0036000291452").canonical)
    }
    @Test func ean8() throws { #expect(try RetailBarcode("96385074").canonical == "96385074") }
    @Test func upce() throws { #expect(try RetailBarcode("04252614", format: .upce).canonical == "0042100005264") }
    @Test func invalidBarcode() {
        #expect((try? RetailBarcode("036000291453")) == nil)
        #expect((try? RetailBarcode("ABC123")) == nil)
    }
    @Test func fractionalNutrition() throws {
        let n = try ServingNutrition(calories: 150, protein: 10, carbohydrates: 12.25, fat: 3.5, fiber: 0)
        #expect(try n.scaled(by: 2.5).calories == 375)
        #expect(try n.scaled(by: 0.5).protein == 5)
        #expect(try n.scaled(by: 0.5).carbohydrates == 6.125)
        #expect(n.calories == 150)
        #expect((try? n.scaled(by: 0)) == nil)
    }
    @Test func invalidNutrition() {
        #expect((try? ServingNutrition(calories: .nan, protein: 0, carbohydrates: 0, fat: 0, fiber: 0)) == nil)
        #expect((try? ServingNutrition(calories: -1, protein: 0, carbohydrates: 0, fat: 0, fiber: 0)) == nil)
    }
    @Test func conversions() {
        #expect(ServingNutrition.grams(ounces: 1) == 28.349523125)
        #expect(ServingNutrition.milliliters(usFluidOunces: 1) == 29.5735295625)
    }
}
