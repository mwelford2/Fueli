import SwiftUI
import SwiftData

struct SavedMealsFlowView: View {
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedMeal.timesLogged, order: .reverse) private var savedMeals: [SavedMeal]
    @State private var mealTypeToLog: MealType = .suggested()

    var body: some View {
        NavigationStack {
            Group {
                if savedMeals.isEmpty {
                    ContentUnavailableView(
                        "No saved meals yet",
                        systemImage: "star",
                        description: Text("Save a meal as a favorite after logging it to see it here.")
                    )
                } else {
                    List {
                        Picker("Meal", selection: $mealTypeToLog) {
                            ForEach(MealType.allCases) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowSeparator(.hidden)

                        ForEach(savedMeals) { meal in
                            Button {
                                logMeal(meal)
                            } label: {
                                HStack(spacing: 12) {
                                    if let data = meal.photoData, let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage).resizable().scaledToFill()
                                            .frame(width: 44, height: 44)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.themeTrack)
                                            .frame(width: 44, height: 44)
                                            .overlay(Image(systemName: "star.fill").foregroundStyle(.secondary))
                                    }
                                    VStack(alignment: .leading) {
                                        Text(meal.name).foregroundStyle(.primary)
                                        Text("\(meal.calories) kcal · \(meal.servingDescription)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    modelContext.delete(meal)
                                    try? modelContext.save()
                                }
                            }
                        }
                    }
                }
            }
            .themedScreenBackground()
            .navigationTitle("Saved Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onFinished() }
                }
            }
        }
    }

    private func logMeal(_ meal: SavedMeal) {
        let log = meal.makeLog(mealType: mealTypeToLog)
        modelContext.insert(log)
        meal.timesLogged += 1
        try? modelContext.save()
        onFinished()
    }
}
