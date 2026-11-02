import SwiftUI
import SwiftData

struct DashboardView: View {
    @Binding var showLogSheet: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeCalories: Double?
    @State private var activityError: String?
    @State private var isRefreshingActivity = false
    @State private var activityRefreshID = UUID()
    @State private var observedToday = Calendar.current.startOfDay(for: Date())
    @State private var healthKit = HealthKitService.shared
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

    private var caloriesConsumed: Int { Int(logsForDay.reduce(0.0) { $0 + $1.caloriesValue }.rounded()) }
    private var proteinConsumed: Double { logsForDay.reduce(0) { $0 + $1.proteinG } }
    private var carbsConsumed: Double { logsForDay.reduce(0) { $0 + $1.carbsG } }
    private var fatConsumed: Double { logsForDay.reduce(0) { $0 + $1.fatG } }
    private var fiberConsumed: Double { logsForDay.reduce(0) { $0 + $1.fiberG } }

    private var yesterdayOvershoot: Int {
        guard let profile else { return 0 }
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else { return 0 }
        let consumed = allLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: yesterday) }
            .reduce(0.0) { $0 + $1.caloriesValue }
        return max(0, Int(consumed.rounded()) - profile.calorieTarget(currentWeightKg: currentWeight))
    }

    private var rolloverAdjustment: Int {
        guard let profile, profile.rolloverExcessCalories, Calendar.current.isDateInToday(selectedDate) else { return 0 }
        let base = profile.calorieTarget(currentWeightKg: currentWeight)
        return min(yesterdayOvershoot, Int(Double(base) * UserProfile.rolloverCapFraction))
    }

    private var calorieTarget: Int {
        guard let profile else { return 0 }
        return profile.calorieTarget(currentWeightKg: currentWeight) - rolloverAdjustment
    }

    private var macroTargets: (protein: Int, carbs: Int, fat: Int) {
        guard let profile else { return (0, 0, 0) }
        return profile.macroTargets(currentWeightKg: currentWeight)
    }

    private var fiberTarget: Int {
        guard let profile else { return 0 }
        return profile.fiberTarget(currentWeightKg: currentWeight)
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
                            activeCalories: activeCalories,
                            rolloverAdjustment: rolloverAdjustment
                        )

                        if let average = profile.maintenanceAverageCalories {
                            Text("Budget uses \(profile.maintenanceSourceLabel.lowercased()): \(Int(average.rounded())) kcal/day (including resting and activity).")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ActivityCard(activeCalories: activeCalories, workouts: workoutsForDay)
                        if isRefreshingActivity { ProgressView("Reading Apple Health…") }
                        if let activityError { Text(activityError).font(.caption).foregroundStyle(.red) }
                        if activeCalories == nil {
                            Text(profile.hasMaintenanceAverage
                                 ? "No readable Active Energy data for this day. Your saved average total burn still determines your calorie plan."
                                 : "No readable Active Energy data for this day. Your configured activity estimate is used. Allow Active Energy access in Health and ensure your device records it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button(healthKit.hasRequestedActiveEnergy ? "Retry Apple Health Connection" : "Connect Apple Health") {
                            Task {
                                do {
                                    try await healthKit.connectActiveEnergy()
                                    await refreshActivity()
                                } catch { activityError = error.localizedDescription }
                            }
                        }.disabled(isRefreshingActivity || !healthKit.isAvailable)

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
                .task(id: selectedDate) {
                    activeCalories = nil
                    while !Task.isCancelled {
                        if scenePhase == .active { await refreshActivity() }
                        do { try await Task.sleep(for: .seconds(60)) } catch { break }
                    }
                }
                .refreshable { await refreshActivity() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await refreshActivity() } }
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

    @MainActor
    private func refreshActivity() async {
        let today = Calendar.current.startOfDay(for: Date())
        if today != observedToday {
            if selectedDate == observedToday { selectedDate = today }
            observedToday = today
        }
        guard healthKit.hasRequestedActiveEnergy else { return }
        let requestID = UUID()
        activityRefreshID = requestID
        let date = selectedDate
        isRefreshingActivity = true
        defer { if requestID == activityRefreshID { isRefreshingActivity = false } }
        do {
            let value = try await healthKit.activeEnergy(on: date)
            guard !Task.isCancelled, date == selectedDate, requestID == activityRefreshID else { return }
            activeCalories = value
            activityError = nil
        } catch {
            guard !Task.isCancelled, date == selectedDate, requestID == activityRefreshID else { return }
            activeCalories = nil
            activityError = "Couldn’t read Apple Health. Pull down to retry. \(error.localizedDescription)"
        }
    }

    private func celebrateIfCrossed(old: Double, new: Double, target: Double) {
        if target > 0 && old < target && new >= target {
            confettiTrigger += 1
        }
    }

}

private struct DateNavigator: View {
    @Binding var date: Date

    var body: some View {
        HStack {
            Button { date = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Text(date, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            Spacer()
            Button { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")
            .disabled(Calendar.current.isDateInToday(date))
        }
    }
}

private struct CalorieRingCard: View {
    let consumed: Int
    let target: Int
    let activeCalories: Double?
    let rolloverAdjustment: Int

    /// HealthKit activity is already included in the target; never add workouts again.
    private var effectiveTarget: Int { target }
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

            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let activeCalories {
                Label("\(Int(activeCalories.rounded())) active kcal · Apple Health", systemImage: "flame.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ActivityCard: View {
    let activeCalories: Double?
    let workouts: [WorkoutLog]


    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Activity", systemImage: "figure.run")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(activeCalories.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.title2.bold()).foregroundStyle(Color.themeFiber)
                Text("active kcal burned so far · Apple Health").font(.caption).foregroundStyle(.secondary)
                Text("Excludes resting energy. Includes activity recorded by Health; workouts below are not added again.")
                    .font(.caption2).foregroundStyle(.secondary)
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
                Text("\(consumed.formatted(.number.precision(.fractionLength(0...1))))g").font(.caption.bold())
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
                    .accessibilityLabel("Undo last water entry")
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

    @State private var editingLog: FoodLog?

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
                        Button { editingLog = log } label: {
                            FoodLogRow(log: log)
                        }
                        .buttonStyle(.plain)
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
        .sheet(item: $editingLog) { log in
            EditMealView(log: log)
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
                Text("\(log.mealType.label) · \(log.servings.formatted()) × \(log.servingDescription)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(log.calories) kcal").font(.themeSubheadline.bold())
                Text("P\(log.proteinG.formatted(.number.precision(.fractionLength(0...1)))) C\(log.carbsG.formatted(.number.precision(.fractionLength(0...1)))) F\(log.fatG.formatted(.number.precision(.fractionLength(0...1)))) Fb\(log.fiberG.formatted(.number.precision(.fractionLength(0...1))))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
