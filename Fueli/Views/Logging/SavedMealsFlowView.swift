import SwiftUI
import SwiftData

/// Legacy favorites remain the per-standard-serving library, with no destructive migration.
struct SavedMealsFlowView: View {
    let onFinished: () -> Void
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMeal.timesLogged, order: .reverse) private var savedMeals: [SavedMeal]
    @State private var search = ""
    @State private var searchPresented = false
    @State private var filter = "All"
    private var visibleFoods: [SavedMeal] {
        let matching = savedMeals.filter { (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) && (filter != "Favorites" || $0.isFavorite) }
        if filter == "Recent" { return matching.sorted { ($0.lastLoggedAt ?? .distantPast) > ($1.lastLoggedAt ?? .distantPast) } }
        if filter == "Frequent" { return matching.sorted { $0.timesLogged > $1.timesLogged } }
        return matching.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    @State private var selected: SavedMeal?
    @State private var pendingDelete: SavedMeal?
    @State private var errorMessage: String?
    @State private var creating = false
    @State private var building = false
    @State private var editingRecipe: SavedMeal?
    @State private var refreshing = false
    @State private var refreshResult: NutritionFacts?
    @State private var refreshedFood: SavedMeal?

    var body: some View {
        NavigationStack {
            List {
                Button("Create Meal") { building = true }
                Button("Create Food Manually") { creating = true }
                Picker("Browse", selection: $filter) { ForEach(["All", "Favorites", "Recent", "Frequent"], id: \.self) { Text($0).tag($0) } }.accessibilityIdentifier("library.filter")
                ForEach(visibleFoods) { meal in
                    Button { selected = meal } label: {
                        VStack(alignment: .leading) {
                            Text(meal.name).foregroundStyle(.primary)
                            if meal.ingredientData != nil { Label("Recipe", systemImage: "list.bullet").font(.caption) }
                            if let source = meal.nutritionSourceID { Text(source).font(.caption).foregroundStyle(.secondary) }
                            Text("\(meal.calories) kcal · \(meal.servingDescription)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("library." + meal.name)
                    .contextMenu {
                        Button(meal.isFavorite ? "Remove Favorite" : "Favorite") { meal.isFavorite.toggle(); try? modelContext.save() }
                        if meal.nutritionSourceID?.hasPrefix("USDA:") == true && meal.ingredientData == nil {
                            Button("Review refreshed USDA nutrition") { refreshUSDA(meal) }
                        }
                        if meal.ingredientData != nil { Button("Edit recipe ingredients") { editingRecipe = meal } }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { pendingDelete = meal } }
                }
                if refreshing { ProgressView("Refreshing USDA details…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .themedScreenBackground()
            .searchable(text: $search, isPresented: $searchPresented)
            .onSubmit(of: .search) { searchPresented = false }
            .navigationTitle("My Foods")
            .toolbar { Button("Close", action: onFinished) }
            .sheet(item: $selected) { meal in
                NutritionConfirmView(result: NutritionFacts(name: meal.name, calories: meal.calories,
                    proteinG: meal.proteinG, carbsG: meal.carbsG, fatG: meal.fatG, fiberG: meal.fiberG,
                    servingDescription: meal.servingDescription, barcode: meal.canonicalBarcode, sourceRecordID: meal.nutritionSourceID, gramsPerServing: meal.gramsPerServing, millilitersPerServing: meal.millilitersPerServing, caloriesExact: meal.caloriesValue), source: .savedMeal, savedMeal: meal, onFinished: onFinished)
            }
            .sheet(item: $refreshResult) { result in
                NutritionConfirmView(result: result, source: .savedMeal, savedMeal: refreshedFood, onFinished: { refreshResult = nil; refreshedFood = nil })
            }
            .sheet(item: $editingRecipe) { recipe in MealBuilderView(onFinished: { editingRecipe = nil }, initialRecipe: recipe) }
            .sheet(isPresented: $building) { MealBuilderView(onFinished: { building = false }) }
            .sheet(isPresented: $creating) { ManualEntryView(onFinished: { creating = false }) }
            .confirmationDialog("Delete this saved food? Historical logs will remain.", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    guard let meal = pendingDelete else { return }
                    modelContext.delete(meal)
                    do { try modelContext.save() } catch { modelContext.rollback(); errorMessage = error.localizedDescription }
                    pendingDelete = nil
                }
            }
        }
    }
    private func refreshUSDA(_ food: SavedMeal) {
        guard !refreshing, let source = food.nutritionSourceID,
              let id = Int(source.replacingOccurrences(of: "USDA:", with: "")),
              let grams = food.gramsPerServing, grams.isFinite, grams > 0 else {
            errorMessage = "A USDA record ID and known gram weight are required to refresh this serving without guessing a conversion."
            return
        }
        refreshing = true; errorMessage = nil
        Task {
            defer { refreshing = false }
            do {
                let values = try await USDAapiCaller.shared.foodDetail(id: id).coreValues()
                func required(_ id: Int) throws -> Double {
                    guard let amount = values[id] else { throw NutritionValidationError.incomplete }; return amount
                }
                let scale = grams / 100
                let c = try required(1008) * scale
                let p = try required(1003) * scale, carbs = try required(1005) * scale
                let fat = try required(1004) * scale, fiber = try required(1079) * scale
                _ = try ServingNutrition(calories: c, protein: p, carbohydrates: carbs, fat: fat, fiber: fiber)
                refreshedFood = food
                refreshResult = NutritionFacts(name: food.name, calories: Int(c.rounded()), proteinG: p, carbsG: carbs,
                    fatG: fat, fiberG: fiber, servingDescription: food.servingDescription, barcode: food.canonicalBarcode,
                    sourceRecordID: source, gramsPerServing: grams, caloriesExact: c)
            } catch { errorMessage = error.localizedDescription }
        }
    }

}
