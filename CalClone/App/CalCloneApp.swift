import SwiftUI
import SwiftData

@main
struct CalCloneApp: App {
    let modelContainer: ModelContainer?

    init() {
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            modelContainer = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: [configuration])
        } catch {
            // Preserve the store and all sidecars for recovery. Never reset user history.
            modelContainer = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer {
                RootView().modelContainer(modelContainer)
            } else {
                ContentUnavailableView("Your data could not be opened", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Your stored history has been retained. Close and reopen Fueli to retry. If this continues, retain the app and contact support before reinstalling."))
            }
        }
    }
}
