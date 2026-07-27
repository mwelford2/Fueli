import SwiftUI
import SwiftData

@main
struct CalCloneApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            UserProfile.self,
            FoodLog.self,
            WeightEntry.self,
            WaterEntry.self,
            SavedMeal.self,
            WorkoutLog.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
