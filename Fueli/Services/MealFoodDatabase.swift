import Foundation

enum MealFoodDatabase: String, CaseIterable, Identifiable {
    case usda, openFoodFacts
    var id: String { rawValue }
    var title: String { self == .usda ? "USDA" : "Open Food Facts" }
    var explanation: String {
        self == .usda
            ? "Generic ingredients and prepared foods. Requires your USDA key."
            : "Packaged products. Free, no key required. Choose the actual product and check its label."
    }
}

/// Builds plain search text, never executable Lucene syntax. Amounts remain in the
/// reviewed component and are applied AFTER a product has been explicitly chosen.
enum IngredientSearchText {
    static func clean(_ text: String) -> String {
        var value = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        value = value.replacingOccurrences(of: #"\b\d+(?:[.,]\d+)?\s*(?:kg|grams?|g|milligrams?|mg|ounces?|oz|pounds?|lbs?|milliliters?|ml|liters?|litres?|cups?|tablespoons?|tbsp|teaspoons?|tsp|slices?|pieces?|servings?)\b"#,
            with: " ", options: .regularExpression)
        // Keep fat percentages as identity information, rather than stripping '2%'.
        value = value.replacingOccurrences(of: "%", with: " percent ")
        value = value.replacingOccurrences(of: #"^\s*\d+(?:[.,]\d+)?\s+(?!percent\b)"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func query(for component: Component) throws -> String {
        let identity = clean(component.label)
        guard !identity.isEmpty else { throw NutritionValidationError.invalidQuantity }
        let methods: Set<String> = ["raw", "cooked", "fried", "grilled", "roasted", "baked", "smoked", "unsalted", "salted", "skinless", "boneless", "breaded", "unbreaded", "unsweetened", "sweetened", "toasted", "steamed", "boiled"]
        let preparation = clean(component.preparation ?? "").split(separator: " ").map(String.init)
            .filter { methods.contains($0) && !identity.split(separator: " ").contains(Substring($0)) }
        let query = ([clean(component.brand ?? ""), identity] + preparation).filter { !$0.isEmpty }.joined(separator: " ")
        guard query.count <= 200 else { throw AIServiceError.requestFailed("Shorten the ingredient or product name before searching.") }
        return query
    }
}

/// Optional, conservative text entry without AI. Only explicit separators split
/// ingredients. 'Mac and cheese', 'peanut butter and jelly', etc. stay intact.
/// Unknown weights stay at zero and must be supplied before any database request.
enum ManualMealDescription {
    static func lookupPlan(from review: NutritionAnalysisResult) -> NutritionAnalysisResult {
        var plan = review
        for index in plan.components.indices {
            let component = plan.components[index]
            plan.components[index].fdcQuery = USDAapiCaller.resolutionQuery(for: component)
            plan.components[index].fallbackQueries = component.label == plan.components[index].fdcQuery ? [] : [component.label]
        }
        return plan
    }

    static func parse(_ text: String) throws -> NutritionAnalysisResult {
        let rows = text.replacingOccurrences(of: #"\s+with\s+"#, with: ";", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !rows.isEmpty, rows.count <= 50, text.count <= 10000 else { throw NutritionValidationError.invalidQuantity }
        let regex = try NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}])([-−]?\d+(?:[.,]\d+)?)\s*(kg|grams?|g|oz|ounces?|lb|lbs|pounds?)\b"#)
        let components = try rows.map { row -> Component in
            var grams = 0.0
            var label = row
            let matches = regex.matches(in: row, range: NSRange(row.startIndex..., in: row))
            if matches.count == 1, let match = matches.first,
               let amountRange = Range(match.range(at: 1), in: row), let unitRange = Range(match.range(at: 2), in: row),
               let fullRange = Range(match.range, in: row),
               let amount = Double(row[amountRange].replacingOccurrences(of: "−", with: "-")) {
                guard amount.isFinite, amount > 0 else { throw NutritionValidationError.invalidQuantity }
                let unit = row[unitRange].lowercased()
                grams = amount * (unit == "kg" ? 1000 : ["oz", "ounce", "ounces"].contains(unit) ? 28.349523125 : ["lb", "lbs", "pound", "pounds"].contains(unit) ? 453.59237 : 1)
                guard grams.isFinite, grams <= 100000 else { throw NutritionValidationError.invalidQuantity }
                label.removeSubrange(fullRange)
                label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let words = Set(label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            let basis: MeasureBasis = words.contains("raw") ? .raw : words.contains("cooked") ? .cooked : .as_packaged
            return Component(label: label, fdcQuery: IngredientSearchText.clean(label), fallbackQueries: [],
                preferredDataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"], brand: nil,
                quantity: Quantity(amount: grams, unit: "g"), estimatedGrams: grams,
                preparation: nil, measureBasis: basis, negligible: false, confidence: 0)
        }
        return NutritionAnalysisResult(dishName: text.trimmingCharacters(in: .whitespacesAndNewlines),
            matchStrategy: .ingredients, composite: nil, components: components,
            totalEstimatedGrams: components.reduce(0) { $0 + $1.estimatedGrams }, confidence: 0,
            needsConfirmation: false, clarifyingQuestion: nil,
            assumptions: ["Entered without AI. Check the ingredient boundaries and enter each weight. Counts and household measures are not converted to grams automatically."])
    }
}

enum MealRecordCalculation {
    static func ingredient(component: Component, reference: NutritionFacts) throws -> LibraryIngredient {
        guard component.measureBasis == .as_packaged else {
            throw AIServiceError.requestFailed("Open Food Facts provides package nutrition. Review this ingredient using an as-packaged weight, or choose USDA for raw/cooked preparation. Cooking can change weight; no conversion was assumed.")
        }
        guard let referenceGrams = reference.gramsPerServing, referenceGrams.isFinite, referenceGrams > 0 else {
            throw AIServiceError.requestFailed("This product does not have a usable gram-based nutrition reference. A milliliter-to-gram conversion cannot be assumed. Choose another record or use USDA/manual entry.")
        }
        guard component.estimatedGrams.isFinite, component.estimatedGrams > 0, component.estimatedGrams <= 100000 else {
            throw NutritionValidationError.invalidQuantity
        }
        let ingredient = LibraryIngredient(id: UUID(), sourceRecordID: reference.sourceRecordID,
            gramsPerServing: referenceGrams, servingDescription: reference.servingDescription,
            preparation: component.preparation, measureBasis: .as_packaged, quantityIsEstimated: true,
            name: reference.name, servings: component.estimatedGrams / referenceGrams,
            calories: reference.caloriesValue, protein: reference.proteinG, carbs: reference.carbsG,
            fat: reference.fatG, fiber: reference.fiberG)
        _ = try ingredient.nutrition()
        return ingredient
    }

    static func assemble(_ description: NutritionAnalysisResult, references: [Int: NutritionFacts]) throws -> NutritionFacts {
        guard !description.components.isEmpty, references.count == description.components.count else { throw NutritionValidationError.incomplete }
        let ingredients = try description.components.enumerated().map { index, component in
            guard let reference = references[index] else { throw NutritionValidationError.incomplete }
            return try ingredient(component: component, reference: reference)
        }
        var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0, fiber = 0.0
        for ingredient in ingredients {
            let n = try ingredient.nutrition()
            calories += n.calories; protein += n.protein; carbs += n.carbohydrates; fat += n.fat; fiber += n.fiber
        }
        let grams = description.components.reduce(0) { $0 + $1.estimatedGrams }
        _ = try ServingNutrition(calories: calories, protein: protein, carbohydrates: carbs, fat: fat, fiber: fiber)
        return NutritionFacts(name: description.dishName, calories: Int(calories.rounded()), proteinG: protein,
            carbsG: carbs, fatG: fat, fiberG: fiber, servingDescription: "\(grams.formatted()) g total · Open Food Facts",
            gramsPerServing: grams, ingredients: ingredients, caloriesExact: calories)
    }
}
