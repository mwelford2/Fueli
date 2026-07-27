import SwiftUI
import SwiftData

struct ProfileSettingsView: View {
    @Bindable var profile: UserProfile
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var weightEntries: [WeightEntry]

    @State private var heightFeetText: String = ""
    @State private var heightInchesText: String = ""
    @State private var heightCmText: String = ""
    @State private var goalWeightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var trackBodyFat = false

    private var currentWeight: Double { weightEntries.first?.weightKg ?? profile.startingWeightKg }

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
                                if let cm = Double(newValue) { profile.heightCm = cm }
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
                                profile.bodyFatPercent = Double(newValue)
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
                                if let value = Double(newValue) { profile.goalWeightKg = profile.weightKg(fromDisplay: value) }
                            }
                        Text(profile.unitSystem.weightUnit).foregroundStyle(.secondary)
                    }
                }
                Picker("Daily Steps", selection: $profile.stepsTier) {
                    ForEach(StepsTier.allCases) { Text($0.label).tag($0) }
                }
                Picker("Weekly Workout Hours", selection: $profile.workoutHoursTier) {
                    ForEach(WorkoutHoursTier.allCases) { Text($0.label).tag($0) }
                }
                Picker("Diet Preference", selection: $profile.dietPreference) {
                    ForEach(DietPreference.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Computed Targets") {
                let calories = profile.calorieTarget(currentWeightKg: currentWeight)
                let macros = profile.macroTargets(currentWeightKg: currentWeight)
                LabeledContent("Calories", value: "\(calories) kcal")
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
        .onAppear {
            heightFeetText = String(profile.heightFeet)
            heightInchesText = String(profile.heightRemainderInches)
            heightCmText = String(format: "%.0f", profile.heightCm)
            goalWeightText = String(format: "%.0f", profile.displayWeight(profile.goalWeightKg))
            if let bf = profile.bodyFatPercent {
                trackBodyFat = true
                bodyFatText = String(format: "%.0f", bf)
            }
        }
    }

    private func saveHeight() {
        guard let feet = Double(heightFeetText), let inches = Double(heightInchesText) else { return }
        profile.heightCm = UnitConversion.inchesToCm(feet * 12 + inches)
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
