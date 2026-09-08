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
            // A store from an older schema version (e.g. one missing a newly added
            // enum-backed property) can fail lightweight migration and throw here rather
            // than falling back to the property's default. There's no server-backed source
            // of truth for this data, so recover by discarding the incompatible on-disk
            // store and starting fresh instead of crashing the app on every launch.
            print("ModelContainer load failed (\(error)); resetting local store.")
            Self.deleteStoreFiles(for: configuration)
            do {
                modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Failed to create ModelContainer even after resetting the store: \(error)")
            }
        }
    }

    private static func deleteStoreFiles(for configuration: ModelConfiguration) {
        guard let url = configuration.url as URL?, url.isFileURL else { return }
        let fileManager = FileManager.default
        // SQLite stores are the main file plus -wal/-shm sidecars; remove whatever exists.
        for suffix in ["", "-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            try? fileManager.removeItem(at: sidecar)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
