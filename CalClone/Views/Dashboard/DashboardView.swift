import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var showLogSheet: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var pedometer = PedometerService.shared
    @State private var confettiTrigger = 0

    @Query private var profiles: [UserProfile]
    @Query private var allLogs: [FoodLog]
    @Query private var allWeights: [WeightEntry]
    @Query private var allWater: [WaterEntry]
    @Query private var allWorkouts: [WorkoutLog]

    private var profile: UserProfile? { profiles.first }

    private var logsForDay: [FoodLog] {
        allLogs.filter { Calendar.current.isDate($0.loggedAt, inSameDayAs: selectedDate) }
            .sorted { $0.loggedAt > $1.loggedAt }
    }

    private var waterEntriesForDay: [WaterEntry] {
        allWater.filter { Calendar.current.isDate($0.recordedAt, inSameDayAs: selectedDate) }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    private var waterForDay: Int {
        waterEntriesForDay.reduce(0) { $0 + $1.amountOz }
    }

    private var workoutsForDay: [WorkoutLog] {
        allWorkouts.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDate) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var workoutCaloriesForDay: Int {
        workoutsForDay.reduce(0) { $0 + $1.caloriesBurned }
    }

    private var currentWeight: Double {
        allWeights.sorted { $0.recordedAt > $1.recordedAt }.first?.weightKg ?? profile?.startingWeightKg ?? 75
    }

    /// Always today's totals (independent of `selectedDate`), so goal celebrations
    /// only fire for genuine same-day progress — not from browsing past days.
    private var todayProtein: Double {
        allLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }.reduce(0) { $0 + $1.proteinG }
    }

    private var todayFiber: Double {
        allLogs.filter { Calendar.current.isDateInToday($0.loggedAt) }.reduce(0) { $0 + $1.fiberG }
    }

    private var todayWater: Int {
        allWater.filter { Calendar.current.isDateInToday($0.recordedAt) }.reduce(0) { $0 + $1.amountOz }
    }

    private var caloriesConsumed: Int { logsForDay.reduce(0) { $0 + $1.calories } }
    private var proteinConsumed: Double { logsForDay.reduce(0) { $0 + $1.proteinG } }
    private var carbsConsumed: Double { logsForDay.reduce(0) { $0 + $1.carbsG } }
    private var fatConsumed: Double { logsForDay.reduce(0) { $0 + $1.fatG } }
    private var fiberConsumed: Double { logsForDay.reduce(0) { $0 + $1.fiberG } }

    /// Live step count for the selected day, from CMPedometer.
    private var liveStepsToday: Int? {
        guard Calendar.current.isDateInToday(selectedDate) else { return nil }
        return pedometer.todaySteps > 0 ? pedometer.todaySteps : nil
    }

    private var yesterdayOvershoot: Int {
        guard let profile else { return 0 }
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else { return 0 }
        let consumed = allLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: yesterday) }
            .reduce(0) { $0 + $1.calories }
        return max(0, consumed - profile.calorieTarget(currentWeightKg: currentWeight))
    }

    private var rolloverAdjustment: Int {
        guard let profile, profile.rolloverExcessCalories, Calendar.current.isDateInToday(selectedDate) else { return 0 }
        let base = profile.calorieTarget(currentWeightKg: currentWeight, liveStepsToday: liveStepsToday)
        return min(yesterdayOvershoot, Int(Double(base) * UserProfile.rolloverCapFraction))
    }

    private var calorieTarget: Int {
        guard let profile else { return 0 }
        return profile.calorieTarget(currentWeightKg: currentWeight, liveStepsToday: liveStepsToday) - rolloverAdjustment
    }

    private var macroTargets: (protein: Int, carbs: Int, fat: Int) {
        guard let profile else { return (0, 0, 0) }
        return profile.macroTargets(currentWeightKg: currentWeight, liveStepsToday: liveStepsToday)
    }

    private var fiberTarget: Int {
        guard let profile else { return 0 }
        return profile.fiberTarget(currentWeightKg: currentWeight, liveStepsToday: liveStepsToday)
    }

    var body: some View {
        if let profile = profile {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        DateNavigator(date: $selectedDate)

                        CalorieRingCard(
                            consumed: caloriesConsumed,
                            target: calorieTarget,
                            workoutCalories: workoutCaloriesForDay,
                            steps: liveStepsToday ?? 0,
                            showSteps: liveStepsToday != nil,
                            rolloverAdjustment: rolloverAdjustment
                        )

                        if !workoutsForDay.isEmpty || liveStepsToday != nil {
                            ActivityCard(
                                steps: liveStepsToday ?? 0,
                                showSteps: liveStepsToday != nil,
                                workouts: workoutsForDay
                            )
                        }

                        MacroRingsCard(
                            protein: (proteinConsumed, macroTargets.protein),
                            carbs: (carbsConsumed, macroTargets.carbs),
                            fat: (fatConsumed, macroTargets.fat),
                            fiber: (fiberConsumed, fiberTarget)
                        )

                        WaterCard(
                            currentOz: waterForDay,
                            targetOz: profile.dailyWaterTargetOz,
                            metric: profile.unitSystem == .metric,
                            onAdd: { amount in
                                // Use current time for today so entries can be sorted by recency;
                                // fall back to selectedDate for past-day logging.
                                let timestamp = Calendar.current.isDateInToday(selectedDate) ? Date() : selectedDate
                                modelContext.insert(WaterEntry(amountOz: amount, recordedAt: timestamp))
                                try? modelContext.save()
                            },
                            onRemoveLast: waterEntriesForDay.isEmpty ? nil : {
                                modelContext.delete(waterEntriesForDay[0])
                                try? modelContext.save()
                            }
                        )

                        LoggedMealsSection(logs: logsForDay) { log in
                            modelContext.delete(log)
                            try? modelContext.save()
                        }
                    }
                    .padding()
                }
                .themedScreenBackground()
                .navigationTitle("Today")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showLogSheet = true } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                    }
                }
                .task {
                    pedometer.startDayTracking()
                    await updateStepsTierIfNeeded(profile: profile)
                }
            }
            .confettiCelebration(trigger: confettiTrigger)
            .onChange(of: todayWater) { old, new in
                celebrateIfCrossed(old: Double(old), new: Double(new), target: Double(profile.dailyWaterTargetOz))
            }
            .onChange(of: todayProtein) { old, new in
                celebrateIfCrossed(old: old, new: new, target: Double(macroTargets.protein))
            }
            .onChange(of: todayFiber) { old, new in
                celebrateIfCrossed(old: old, new: new, target: Double(fiberTarget))
            }
        }
    }

    private func celebrateIfCrossed(old: Double, new: Double, target: Double) {
        if target > 0 && old < target && new >= target {
            confettiTrigger += 1
        }
    }

    /// Queries the 14-day rolling average step count from CMPedometer and updates
    /// the profile's stepsTier if it no longer matches the observed activity level.
    private func updateStepsTierIfNeeded(profile: UserProfile) async {
        guard let averageSteps = await pedometer.queryAverageSteps(overPastDays: 14) else { return }
        let newTier = StepsTier.matching(steps: averageSteps)
        guard newTier != profile.stepsTier else { return }
        profile.stepsTier = newTier
    }
}

private struct DateNavigator: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Button { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            Spacer()
            Button { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(Calendar.current.isDateInToday(date))
        }
    }
}

private struct CalorieRingCard: View {
    let consumed: Int
    let target: Int
    let workoutCalories: Int
    let steps: Int
    let showSteps: Bool
    let rolloverAdjustment: Int

    /// Workout calories earned expand the effective daily budget.
    private var effectiveTarget: Int { target + workoutCalories }
    private var overshoot: Int { max(0, consumed - effectiveTarget) }
    private var remaining: Int { max(0, effectiveTarget - consumed) }
    private var progress: Double { effectiveTarget > 0 ? min(1.0, Double(consumed) / Double(effectiveTarget)) : 0 }
    private var ringColor: Color { overshoot > 0 ? .themeProtein : .accentColor }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.themeTrack, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack {
                    Text("\(overshoot > 0 ? overshoot : remaining)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(overshoot > 0 ? Color.themeProtein : .primary)
                    Text(overshoot > 0 ? "kcal over" : "kcal left")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 160, height: 160)
            .animation(.easeInOut, value: progress)

            if rolloverAdjustment > 0 {
                Label("Budget trimmed by \(rolloverAdjustment) kcal to balance yesterday's overage", systemImage: "arrow.uturn.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Label("\(consumed) eaten", systemImage: "fork.knife")
                Spacer()
                if workoutCalories > 0 {
                    Label("+\(workoutCalories) earned", systemImage: "flame.fill")
                        .foregroundStyle(Color.themeFiber)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if showSteps {
                HStack {
                    Label("\(steps) steps today", systemImage: "figure.walk")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ActivityCard: View {
    let steps: Int
    let showSteps: Bool
    let workouts: [WorkoutLog]

    private var totalCaloriesBurned: Int { workouts.reduce(0) { $0 + $1.caloriesBurned } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activity", systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 24) {
                if showSteps {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(steps)")
                            .font(.title2.bold())
                        Text("steps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if totalCaloriesBurned > 0 {
                    if showSteps { Divider().frame(height: 36) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(totalCaloriesBurned)")
                            .font(.title2.bold())
                            .foregroundStyle(Color.themeFiber)
                        Text("kcal burned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if !workouts.isEmpty {
                Divider()
                ForEach(workouts) { workout in
                    HStack(spacing: 10) {
                        Image(systemName: workout.workoutType.icon)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                        Text(workout.workoutType.label)
                            .font(.caption.bold())
                        Spacer()
                        Text("\(workout.durationSeconds / 60) min · \(workout.caloriesBurned) kcal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MacroRingsCard: View {
    let protein: (Double, Int)
    let carbs: (Double, Int)
    let fat: (Double, Int)
    let fiber: (Double, Int)

    var body: some View {
        HStack(spacing: 12) {
            MacroRing(label: "Protein", consumed: protein.0, target: protein.1, color: .themeProtein)
            MacroRing(label: "Carbs", consumed: carbs.0, target: carbs.1, color: .themeCarbs)
            MacroRing(label: "Fat", consumed: fat.0, target: fat.1, color: .themeFat)
            MacroRing(label: "Fiber", consumed: fiber.0, target: fiber.1, color: .themeFiber)
        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct MacroRing: View {
    let label: String
    let consumed: Double
    let target: Int
    let color: Color

    private var progress: Double { target > 0 ? min(1.0, consumed / Double(target)) : 0 }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.themeTrack, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(consumed))g").font(.caption.bold())
            }
            .frame(width: 64, height: 64)
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("of \(target)g").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WaterCard: View {
    let currentOz: Int
    let targetOz: Int
    let metric: Bool
    let onAdd: (Int) -> Void
    let onRemoveLast: (() -> Void)?

    /// Water is stored in oz; metric mode only changes the display.
    private func formatted(_ oz: Int) -> String {
        metric ? "\(Int(UnitConversion.ozToMl(Double(oz)).rounded())) ml" : "\(oz) oz"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Water", systemImage: "drop.fill").font(.headline).foregroundStyle(Color.themeWater)
                Spacer()
                if let onRemoveLast {
                    Button { onRemoveLast() } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("\(formatted(currentOz)) / \(formatted(targetOz))").font(.themeSubheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(currentOz), total: Double(max(targetOz, 1)))
                .tint(.themeWater)
            HStack(spacing: 12) {
                ForEach([8, 16, 24], id: \.self) { amount in
                    Button("+\(formatted(amount))") { onAdd(amount) }
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct LoggedMealsSection: View {
    let logs: [FoodLog]
    let onDelete: (FoodLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logged").font(.headline)
            if logs.isEmpty {
                Text("Nothing logged yet. Tap + to add a meal.")
                    .font(.themeSubheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(logs) { log in
                    HStack {
                        FoodLogRow(log: log)
                        Button { onDelete(log) } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { onDelete(log) }
                    }
                }
            }
        }
    }
}

struct FoodLogRow: View {
    let log: FoodLog

    var body: some View {
        HStack(spacing: 12) {
            if let data = log.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.themeTrack)
                    .frame(width: 48, height: 48)
                    .overlay(Image(systemName: log.mealType.icon).foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(log.name).font(.themeSubheadline.bold())
                Text("\(log.mealType.label) · \(log.servingDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(log.calories) kcal").font(.themeSubheadline.bold())
                Text("P\(Int(log.proteinG)) C\(Int(log.carbsG)) F\(Int(log.fatG)) Fb\(Int(log.fiberG))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
