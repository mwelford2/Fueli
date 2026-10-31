import Foundation

// Compile with ServingNutrition.swift and RetailBarcode.swift; no network or app state.
enum BarcodeLookupError: Error { case requestFailed(String) }

@main struct NutritionRegression {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () throws -> Bool) rethrows {
            let passed = try condition()
            precondition(passed); checks += 1
        }
        try check(RetailBarcode("036000291452").canonical == "0036000291452")
        try check(RetailBarcode("0036000291452").canonical == "0036000291452")
        try check(RetailBarcode("96385074").canonical == "96385074")
        try check(RetailBarcode("04252614", format: .upce).canonical == "0042100005264")
        check((try? RetailBarcode("036000291453")) == nil)
        check((try? RetailBarcode("123abc")) == nil)
        check((try? RetailBarcode("123")) == nil)
        let n = try ServingNutrition(calories: 150, protein: 10, carbohydrates: 12.25, fat: 3.5, fiber: 0)
        try check(n.scaled(by: 2.5).calories == 375)
        try check(n.scaled(by: 0.5).protein == 5)
        try check(n.scaled(by: 0.5).carbohydrates == 6.125)
        check(n.calories == 150)
        check((try? n.scaled(by: 0)) == nil)
        check((try? n.scaled(by: .infinity)) == nil)
        check((try? ServingNutrition(calories: .nan, protein: 0, carbohydrates: 0, fat: 0, fiber: 0)) == nil)
        check((try? ServingNutrition(calories: -1, protein: 0, carbohydrates: 0, fat: 0, fiber: 0)) == nil)
        check(abs(ServingNutrition.grams(ounces: 1) - 28.349523125) < 1e-10)
        check(abs(ServingNutrition.milliliters(usFluidOunces: 1) - 29.5735295625) < 1e-10)
        print("\(checks) deterministic nutrition/barcode regression checks passed")
    }
}
