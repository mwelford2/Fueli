import SwiftUI
import SwiftData

struct RootView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if let profile = profiles.first {
                if profile.hasCompletedOnboarding {
                    MainTabView(profile: profile)
                } else {
                    OnboardingFlowView(profile: profile)
                }
            } else {
                Color.clear.onAppear(perform: createProfile)
            }
        }
    }

    private func createProfile() {
        let profile = UserProfile()
        modelContext.insert(profile)
        try? modelContext.save()
    }
}

// MARK: - Preview support

/// In-memory containers so the full app can run interactively in the preview canvas.
@MainActor
enum PreviewData {
    static let fullSchema: [any PersistentModel.Type] = [
        UserProfile.self, FoodLog.self, WeightEntry.self, WaterEntry.self, SavedMeal.self
    ]

    /// Empty container — RootView creates a fresh profile and starts onboarding.
    static func emptyContainer() -> ModelContainer {
        try! ModelContainer(
            for: Schema(fullSchema),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Container seeded with an onboarded profile and realistic sample data, so the
    /// dashboard, history, streaks, and settings all have content to show.
    static func seededContainer() -> ModelContainer {
        let container = emptyContainer()
        let context = container.mainContext
        let calendar = Calendar.current

        let profile = UserProfile(hasCompletedOnboarding: true, bodyFatPercent: 18)
        context.insert(profile)

        // Two weeks of weight trending toward the goal.
        for daysAgo in stride(from: 14, through: 0, by: -2) {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
            let weight = profile.startingWeightKg - Double(14 - daysAgo) * 0.07
            context.insert(WeightEntry(weightKg: weight, recordedAt: date))
        }

        // Meals across the last few days, including today.
        let sampleMeals: [(String, Int, Double, Double, Double, Double, MealType)] = [
            ("Greek Yogurt & Berries", 320, 22, 38, 9, 5, .breakfast),
            ("Chicken Burrito Bowl", 650, 45, 62, 22, 12, .lunch),
            ("Salmon, Rice & Broccoli", 580, 42, 48, 21, 6, .dinner),
            ("Protein Shake", 210, 30, 12, 4, 2, .snack)
        ]
        for daysAgo in 0...4 {
            for (name, cals, p, c, f, fb, meal) in sampleMeals {
                let hour: Int
                switch meal {
                case .breakfast: hour = 8
                case .lunch: hour = 12
                case .dinner: hour = 19
                case .snack: hour = 15
                }
                var components = calendar.dateComponents(
                    [.year, .month, .day],
                    from: calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
                )
                components.hour = hour
                context.insert(FoodLog(
                    name: name, calories: cals, proteinG: p, carbsG: c, fatG: f, fiberG: fb,
                    mealType: meal, loggedAt: calendar.date(from: components)!, source: .manual
                ))
            }
        }

        // Water for today.
        for _ in 0..<3 {
            context.insert(WaterEntry(amountOz: 16))
        }

        // Saved meals for the quick-log flow.
        context.insert(SavedMeal(name: "Chicken Burrito Bowl", calories: 650, proteinG: 45, carbsG: 62, fatG: 22, timesLogged: 8))
        context.insert(SavedMeal(name: "Overnight Oats", calories: 410, proteinG: 24, carbsG: 55, fatG: 11, timesLogged: 5))
        context.insert(SavedMeal(name: "Protein Shake", calories: 210, proteinG: 30, carbsG: 12, fatG: 4, timesLogged: 12))

        try? context.save()
        return container
    }
}

#Preview("Full App") {
    RootView()
        .modelContainer(PreviewData.seededContainer())
}

#Preview("Fresh Install (Onboarding)") {
    RootView()
        .modelContainer(PreviewData.emptyContainer())
}
