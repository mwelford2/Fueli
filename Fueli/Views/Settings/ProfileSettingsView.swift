import SwiftUI
import SwiftData

struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var weightEntries: [WeightEntry]
    @Environment(\.modelContext) private var modelContext

    @State private var heightFeetText: String = ""
    @State private var heightInchesText: String = ""
    @State private var heightCmText: String = ""
    @State private var currentWeightText: String = ""
    @State private var goalWeightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var trackBodyFat = false
    @FocusState private var weightFieldFocused: Bool
    @State private var hasChanges = false
    @State private var showSavedToast = false

    private var currentWeight: Double { weightEntries.first?.weightKg ?? profile.startingWeightKg }

    @State private var isReadingHealth = false
    @State private var healthImportMessage: String?

    var body: some View {
        Form {
            Section("About You") {
                Picker("Sex", selection: $profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                DatePicker("Birth Date", selection: $profile.birthDate, displayedComponents: .date)
                if profile.unitSystem == .metric {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", text: $heightCmText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: heightCmText) { _, newValue in
                                if let cm = Double(newValue), EntryValidation.heightCm(cm), abs(cm - profile.heightCm) > 0.01 {
                                    profile.heightCm = cm
                                }
                            }
                        Text("cm").foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("ft", text: $heightFeetText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 40)
                            .onChange(of: heightFeetText) { _, _ in saveHeight() }
                        Text("ft").foregroundStyle(.secondary)
                        TextField("in", text: $heightInchesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 40)
                            .onChange(of: heightInchesText) { _, _ in saveHeight() }
                        Text("in").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Current Weight")
                    Spacer()
                    TextField(profile.unitSystem.weightUnit, text: $currentWeightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($weightFieldFocused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                if weightFieldFocused {
                                    Spacer()
                                    Button("Done") {
                                        logCurrentWeight()
                                        weightFieldFocused = false
                                    }
                                }
                            }
                        }
                    Text(profile.unitSystem.weightUnit).foregroundStyle(.secondary)
                }
                Toggle("I know my body fat %", isOn: $trackBodyFat.animation())
                    .onChange(of: trackBodyFat) { _, isOn in
                        if !isOn { profile.bodyFatPercent = nil }
                    }
                if trackBodyFat {
                    HStack {
                        Text("Body Fat")
                        Spacer()
                        TextField("%", text: $bodyFatText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            .onChange(of: bodyFatText) { _, newValue in
                                if newValue.isEmpty { profile.bodyFatPercent = nil }
                                else if let value = Double(newValue), EntryValidation.bodyFat(value) { profile.bodyFatPercent = value }
                            }
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Goal") {
                Picker("Goal", selection: $profile.trainingGoal) {
                    ForEach(TrainingGoal.allCases) { Text($0.label).tag($0) }
                }
                if profile.trainingGoal == .recomp {
                    Picker("Recomp Focus", selection: $profile.recompFocus) {
                        ForEach(RecompFocus.allCases) { Text($0.label).tag($0) }
                    }
                } else {
                    HStack {
                        Text("Goal Weight")
                        Spacer()
                        TextField(profile.unitSystem.weightUnit, text: $goalWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: goalWeightText) { _, newValue in
                                if let value = Double(newValue) {
                                    let newKg = profile.weightKg(fromDisplay: value)
                                    if EntryValidation.weightKg(newKg), abs(newKg - profile.goalWeightKg) > 0.01 {
                                        profile.goalWeightKg = newKg
                                    }
                                }
                            }
                        Text(profile.unitSystem.weightUnit).foregroundStyle(.secondary)
                    }
                }
                ManualBurnInput(profile: profile, weightKg: currentWeight, onApplied: { hasChanges = true })
                if let average = profile.maintenanceAverageCalories {
                    LabeledContent(profile.maintenanceSourceLabel, value: "\(Int(average.rounded())) kcal/day")
                    Text("This full-day total replaces resting, step and workout estimates. Your goal adjustment determines intake.").font(.caption)
                }
                if profile.hasManualMaintenance {
                    Text("Importing a valid Health average switches from manual burn to Health. Insufficient history keeps the manual burn.").font(.caption)
                }
                Button(profile.hasHealthMaintenance ? "Refresh Health total-energy average" : "Use Health total-energy average") {
                    Task {
                        isReadingHealth = true
                        defer { isReadingHealth = false }
                        do {
                            try await HealthKitService.shared.connectTotalEnergy()
                            if let average = try await HealthKitService.shared.averageTotalEnergy() {
                                profile.manualMaintenanceCalories = nil
                                profile.healthMaintenanceCalories = average.calories
                                profile.healthEnergyDayCount = average.days
                                profile.healthEnergyWindowStart = average.start
                                profile.healthEnergyWindowEnd = average.end
                                try modelContext.save()
                                healthImportMessage = "Updated from completed days of resting + active energy."
                            } else { healthImportMessage = HealthKitService.shared.historySummary + " Previous settings are retained." }
                        } catch { healthImportMessage = "Couldn’t update Health history: " + error.localizedDescription }
                    }
                }.disabled(isReadingHealth)
                if isReadingHealth { ProgressView() }
                if let healthImportMessage { Text(healthImportMessage).font(.caption) }
                if profile.hasMaintenanceAverage {
                    Button("Use activity estimates instead") {
                        profile.useActivityEstimates()
                        hasChanges = true
                    }
                    if let end = profile.healthEnergyWindowEnd {
                        Text("History window ends \(end.formatted(date: .abbreviated, time: .omitted)) (exclusive). Refresh when activity changes.").font(.caption)
                    }
                }
                Picker("Daily Steps", selection: $profile.stepsTier) {
                    ForEach(StepsTier.allCases) { Text($0.label).tag($0) }
                }
                Picker("Weekly Workout Hours", selection: $profile.workoutHoursTier) {
                    ForEach(WorkoutHoursTier.allCases) { Text($0.label).tag($0) }
                }
                if profile.hasMaintenanceAverage {
                    Text("Step and workout estimates are ignored while an average daily burn is selected.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Diet Preference", selection: $profile.dietPreference) {
                    ForEach(DietPreference.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Computed Targets") {
                CalorieEvidenceLinks()
                let calories = profile.calorieTarget(currentWeightKg: currentWeight)
                let macros = profile.macroTargets(currentWeightKg: currentWeight)
                LabeledContent("Maintenance burn", value: "\(Int(profile.tdee(currentWeightKg: currentWeight).rounded())) kcal/day")
                LabeledContent("Goal adjustment", value: "\(Int(profile.dailyCalorieDelta(maintenance: profile.tdee(currentWeightKg: currentWeight), weightKg: currentWeight).rounded())) kcal/day")
                LabeledContent("Calories to eat", value: "\(calories) kcal/day")
                LabeledContent("Protein", value: "\(macros.protein) g")
                LabeledContent("Carbs", value: "\(macros.carbs) g")
                LabeledContent("Fat", value: "\(macros.fat) g")
                LabeledContent("Fiber", value: "\(profile.fiberTarget(currentWeightKg: currentWeight)) g")
            }

            Section {
                Toggle("Override targets manually", isOn: Binding(
                    get: { profile.manualCalorieTarget != nil },
                    set: { enabled in
                        if enabled {
                            let calories = profile.calorieTarget(currentWeightKg: currentWeight)
                            let macros = profile.macroTargets(currentWeightKg: currentWeight)
                            profile.manualCalorieTarget = calories
                            profile.manualProteinTarget = macros.protein
                            profile.manualCarbTarget = macros.carbs
                            profile.manualFatTarget = macros.fat
                            profile.manualFiberTarget = profile.fiberTarget(currentWeightKg: currentWeight)
                        } else {
                            profile.manualCalorieTarget = nil
                            profile.manualProteinTarget = nil
                            profile.manualCarbTarget = nil
                            profile.manualFatTarget = nil
                            profile.manualFiberTarget = nil
                        }
                    }
                ))

                if profile.manualCalorieTarget != nil {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("kcal", value: $profile.manualCalorieTarget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        TextField("g", value: $profile.manualProteinTarget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Carbs (g)")
                        Spacer()
                        TextField("g", value: $profile.manualCarbTarget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Fat (g)")
                        Spacer()
                        TextField("g", value: $profile.manualFatTarget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                    HStack {
                        Text("Fiber (g)")
                        Spacer()
                        TextField("g", value: $profile.manualFiberTarget, format: .number)
                            .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                    }
                }
            }
        }
        .themedScreenBackground()
        .navigationTitle("Goals & Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.themeOlive)
                        .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if showSavedToast {
                SavedToastView()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 24)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hasChanges)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSavedToast)
        .modifier(ProfileChangeObserver(profile: profile, hasChanges: $hasChanges))
        .onAppear {
            heightFeetText = String(profile.heightFeet)
            heightInchesText = String(profile.heightRemainderInches)
            heightCmText = String(format: "%.0f", profile.heightCm)
            currentWeightText = String(format: "%.1f", profile.displayWeight(currentWeight))
            goalWeightText = String(format: "%.0f", profile.displayWeight(profile.goalWeightKg))
            if let bf = profile.bodyFatPercent {
                trackBodyFat = true
                bodyFatText = String(format: "%.0f", bf)
            }
        }
    }

    private func saveChanges() {
        try? modelContext.save()
        hasChanges = false
        withAnimation {
            showSavedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                showSavedToast = false
            }
        }
    }

    private func logCurrentWeight() {
        guard let value = Double(currentWeightText) else { return }
        let kg = profile.weightKg(fromDisplay: value)
        guard EntryValidation.weightKg(kg) else { return }
        modelContext.insert(WeightEntry(weightKg: kg))
    }

    private func saveHeight() {
        guard let feet = Double(heightFeetText), let inches = Double(heightInchesText) else { return }
        let newCm = UnitConversion.inchesToCm(feet * 12 + inches)
        guard EntryValidation.heightCm(newCm), (0..<12).contains(inches), feet >= 0 else { return }
        guard abs(newCm - profile.heightCm) > 0.01 else { return }
        profile.heightCm = newCm
    }
}

private struct ProfileChangeObserver: ViewModifier {
    var profile: UserProfile
    @Binding var hasChanges: Bool

    func body(content: Content) -> some View {
        content
            .onChange(of: profile.manualMaintenanceCalories) { _, _ in hasChanges = true }
            .onChange(of: profile.sex) { _, _ in hasChanges = true }
            .onChange(of: profile.birthDate) { _, _ in hasChanges = true }
            .onChange(of: profile.heightCm) { _, _ in hasChanges = true }
            .onChange(of: profile.trainingGoal) { _, _ in hasChanges = true }
            .onChange(of: profile.recompFocus) { _, _ in hasChanges = true }
            .onChange(of: profile.stepsTier) { _, _ in hasChanges = true }
            .onChange(of: profile.workoutHoursTier) { _, _ in hasChanges = true }
            .onChange(of: profile.dietPreference) { _, _ in hasChanges = true }
            .onChange(of: profile.goalWeightKg) { _, _ in hasChanges = true }
            .onChange(of: profile.bodyFatPercent) { _, _ in hasChanges = true }
            .onChange(of: profile.manualCalorieTarget) { _, _ in hasChanges = true }
            .onChange(of: profile.manualProteinTarget) { _, _ in hasChanges = true }
            .onChange(of: profile.manualCarbTarget) { _, _ in hasChanges = true }
            .onChange(of: profile.manualFatTarget) { _, _ in hasChanges = true }
            .onChange(of: profile.manualFiberTarget) { _, _ in hasChanges = true }
    }
}

private struct SavedToastView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.themeSage)
            Text("Changes saved")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.themeInk, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: UserProfile.self, WeightEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let profile = UserProfile(hasCompletedOnboarding: true)
    container.mainContext.insert(profile)
    container.mainContext.insert(WeightEntry(weightKg: profile.startingWeightKg))
    return NavigationStack {
        ProfileSettingsView(profile: profile)
    }
    .modelContainer(container)
}
