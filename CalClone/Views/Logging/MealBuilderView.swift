import SwiftUI
import SwiftData

struct MealBuilderView: View {
    let onFinished: () -> Void
    var initialRecipe: SavedMeal? = nil
    @Environment(\.modelContext) private var context
    @Query private var foods: [SavedMeal]
    @State private var name = "My Meal"
    @State private var ingredients: [LibraryIngredient] = []
    @State private var search = ""
    @State private var error: String?
    @State private var mealType = MealType.suggested()
    private var total: ServingNutrition? {
        do {
            var c = 0.0, p = 0.0, carbs = 0.0, fat = 0.0, fiber = 0.0
            for item in ingredients {
                let n = try item.nutrition()
                c += n.calories; p += n.protein; carbs += n.carbohydrates; fat += n.fat; fiber += n.fiber
            }
            return try ServingNutrition(calories: c, protein: p, carbohydrates: carbs, fat: fat, fiber: fiber)
        } catch { return nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    Picker("Meal type", selection: $mealType) { ForEach(MealType.allCases) { Text($0.label).tag($0) } }
                    Text("The combined ingredient amounts define one standard portion of this recipe.").font(.caption)
                }
                Section("Ingredients — standard servings") {
                    ForEach($ingredients) { $item in
                        VStack(alignment: .leading) {
                            Text(item.name)
                            if let definition = item.servingDescription { Text("Standard: " + definition).font(.caption) }
                            ServingSelector(servings: $item.servings)
                            if let grams = item.gramsPerServing, grams.isFinite, grams > 0 {
                                HStack {
                                    Text("Grams")
                                    TextField("Grams", value: Binding(get: { item.servings * grams }, set: { item.servings = $0 / grams }), format: .number).keyboardType(.decimalPad)
                                }
                                HStack {
                                    Text("Ounces")
                                    TextField("Ounces", value: Binding(get: { item.servings * grams / 28.349523125 }, set: { item.servings = ServingNutrition.grams(ounces: $0) / grams }), format: .number).keyboardType(.decimalPad)
                                }
                            }
                            if let ml = item.millilitersPerServing, ml.isFinite, ml > 0 {
                                HStack {
                                    Text("Milliliters")
                                    TextField("mL", value: Binding(get: { item.servings * ml }, set: { item.servings = $0 / ml }), format: .number).keyboardType(.decimalPad)
                                }
                                HStack {
                                    Text("US fluid ounces")
                                    TextField("fl oz", value: Binding(get: { item.servings * ml / 29.5735295625 }, set: { item.servings = ServingNutrition.milliliters(usFluidOunces: $0) / ml }), format: .number).keyboardType(.decimalPad)
                                }
                            }
                            Button("Remove ingredient", role: .destructive) { ingredients.removeAll { $0.id == item.id } }
                        }
                    }
                }
                Section("Add saved food") {
                    TextField("Search My Foods", text: $search)
                    ForEach(foods.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { food in
                        Button(food.name + " · " + food.servingDescription) {
                            ingredients.append(LibraryIngredient(id: UUID(), foodID: food.id, sourceRecordID: food.nutritionSourceID, gramsPerServing: food.gramsPerServing, millilitersPerServing: food.millilitersPerServing, servingDescription: food.servingDescription, name: food.name, servings: 1,
                                calories: food.caloriesValue, protein: food.proteinG, carbs: food.carbsG, fat: food.fatG, fiber: food.fiberG))
                        }
                    }
                }
                Section("Calculated totals") {
                    if let n = total {
                        Text("\(Int(n.calories.rounded())) kcal · Protein \(n.protein.formatted()) g · Carbs \(n.carbohydrates.formatted()) g · Fat \(n.fat.formatted()) g")
                    }
                    Button("Log Meal") { commit(save: false) }.disabled(!valid)
                    Button("Save Recipe to My Foods") { commit(save: true) }.disabled(!valid)
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }.themedScreenBackground().navigationTitle("Create Meal")
                .toolbar { Button("Close", action: onFinished) }
                .onAppear {
                    if let recipe = initialRecipe, let data = recipe.ingredientData,
                       let decoded = try? JSONDecoder().decode([LibraryIngredient].self, from: data) {
                        name = recipe.name; ingredients = decoded
                    }
                }
        }
    }
    private var valid: Bool { !ingredients.isEmpty && total != nil && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private func commit(save: Bool) {
        guard valid, let n = total else { return }
        do {
            if save {
                let recipe = initialRecipe ?? SavedMeal(name: name, calories: Int(n.calories.rounded()), proteinG: n.protein,
                    carbsG: n.carbohydrates, fatG: n.fat, fiberG: n.fiber, servingDescription: "1 recipe portion")
                recipe.name = name; recipe.calories = Int(n.calories.rounded()); recipe.caloriesExact = n.calories; recipe.proteinG = n.protein
                recipe.carbsG = n.carbohydrates; recipe.fatG = n.fat; recipe.fiberG = n.fiber
                recipe.ingredientData = try JSONEncoder().encode(ingredients)
                // Ingredient mass can change during preparation. A finished recipe's mass
                // must be explicitly defined in its confirmation screen, not inferred.
                recipe.gramsPerServing = nil
                recipe.millilitersPerServing = nil
                context.insert(recipe)
            } else {
                let log = FoodLog(name: name, calories: Int(n.calories.rounded()), proteinG: n.protein,
                    carbsG: n.carbohydrates, fatG: n.fat, fiberG: n.fiber, servingDescription: "1 recipe portion",
                    mealType: mealType, source: .savedMeal, notes: ingredients.map { "\($0.name): \($0.servings) standard servings" }.joined(separator: "\n"))
                log.caloriesExact = n.calories
                log.savedFoodID = initialRecipe?.id
                log.recipeIngredientsData = try JSONEncoder().encode(ingredients)
                context.insert(log)
            }
            try context.save(); onFinished()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
