import SwiftUI
import SwiftData

struct OnboardingFlowView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext

    @State private var step = 0
    @State private var heightFeetText: String = ""
    @State private var heightInchesText: String = ""
    @State private var heightCmText: String = ""
    @State private var weightText: String = ""
    @State private var goalWeightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var trackBodyFat = false
    init(profile: UserProfile, startStep: Int = 0) {
        self.profile = profile
        _step = State(initialValue: startStep)
    }
    
    var age: Int {
            Calendar.current.dateComponents([.year], from: profile.birthDate, to: Date()).year ?? 0
        }

    private var totalSteps: Int { stepSequence.count }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: Double(step + 1), total: Double(totalSteps))
                    .tint(.accentColor)
                    .padding(.horizontal)
                    .animation(.easeInOut, value: step)

                Spacer()

                currentStepView
                    .padding(.horizontal)

                Spacer()

                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button(isLastStep ? "Finish" : "Next") {
                        advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdvance)
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle("Set Up Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Units", selection: unitSystemBinding) {
                            ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                        }
                    } label: {
                        Label(profile.unitSystem.weightUnit, systemImage: "arrow.left.arrow.right.circle")
                    }
                }
            }
        }
        .onAppear {
            heightFeetText = String(profile.heightFeet)
            heightInchesText = String(profile.heightRemainderInches)
            heightCmText = String(format: "%.0f", profile.heightCm)
            weightText = String(format: "%.0f", profile.displayWeight(profile.startingWeightKg))
            goalWeightText = String(format: "%.0f", profile.displayWeight(profile.goalWeightKg))
        }
    }

    // MARK: - Units

    private var unitSystemBinding: Binding<UnitSystem> {
        Binding(
            get: { profile.unitSystem },
            set: { switchUnits(to: $0) }
        )
    }

    /// Re-expresses any weights already typed in when the unit system changes,
    /// so the visible numbers stay equivalent.
    private func switchUnits(to newSystem: UnitSystem) {
        let oldSystem = profile.unitSystem
        guard newSystem != oldSystem else { return }
        profile.unitSystem = newSystem
        for text in [$weightText, $goalWeightText] {
            if let value = Double(text.wrappedValue) {
                let kg = oldSystem == .metric ? value : UnitConversion.lbToKg(value)
                text.wrappedValue = String(format: "%.0f", newSystem == .metric ? kg : UnitConversion.kgToLb(kg))
            }
        }
        // Height: derive cm from whichever fields were active, then re-seed both forms.
        let cm: Double
        if oldSystem == .metric, let value = Double(heightCmText) {
            cm = value
        } else if let feet = Double(heightFeetText), let inches = Double(heightInchesText) {
            cm = UnitConversion.inchesToCm(feet * 12 + inches)
        } else {
            cm = profile.heightCm
        }
        heightCmText = String(format: "%.0f", cm)
        let totalInches = Int(UnitConversion.cmToTotalInches(cm).rounded())
        heightFeetText = String(totalInches / 12)
        heightInchesText = String(totalInches % 12)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch resolvedStep {
        case .sex: sexStep
        case .birthDate: birthDateStep
        case .heightWeight: heightWeightStep
        case .bodyFat: bodyFatStep
        case .goal: goalStep
        case .recompFocus: recompFocusStep
        case .rate: rateStep
        case .steps: stepsStep
        case .workoutHours: workoutHoursStep
        case .diet: dietStep
        case .summary: summaryStep
        case .aiSetup: aiSetupStep
        }
    }

    // MARK: - Step sequencing

    private enum Step {
        case sex, birthDate, heightWeight, bodyFat, goal, recompFocus, rate, steps, workoutHours, diet, summary, aiSetup
    }

    /// Recomp inserts an extra "focus" step and skips the rate slider (recomp's calorie
    /// delta is derived from the focus choice, not a weekly rate).
    private var stepSequence: [Step] {
        var sequence: [Step] = [.sex, .birthDate, .heightWeight, .bodyFat, .goal]
        if profile.trainingGoal == .recomp {
            sequence.append(.recompFocus)
        } else {
            sequence.append(.rate)
        }
        sequence.append(contentsOf: [.steps, .workoutHours, .diet, .summary, .aiSetup])
        return sequence
    }

    private var resolvedStep: Step {
        let sequence = stepSequence
        return sequence[min(step, sequence.count - 1)]
    }

    private var isLastStep: Bool { resolvedStep == .aiSetup }

    // MARK: - Steps

    private var sexStep: some View {
        VStack(spacing: 16) {
            Text("What's your sex?").font(.title2.bold())
            Text("Used to estimate your calorie needs accurately.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
            ForEach(BiologicalSex.allCases) { sex in
                SelectableRow(title: sex.label, isSelected: profile.sex == sex) {
                    profile.sex = sex
                }
            }
        }
    }

    private var birthDateStep: some View {
        VStack(spacing: 16) {
            Text("When were you born?").font(.title2.bold())
            DatePicker("", selection: $profile.birthDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            Text("\(profile.birthDate, format: .dateTime.month().day().year())").font(.title3.bold())
            Text("You are \(age) years old.")
        }
    }

    private var heightWeightStep: some View {
        VStack(spacing: 16) {
            Text("Height & current weight").font(.title2.bold())

            VStack(spacing: 0) {
                heightRow.padding()
                Divider().padding(.leading)
                weightRow.padding()
            }
            .background(Color.themeCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var heightRow: some View {
        HStack {
            Text("Height")
            Spacer()
            if profile.unitSystem == .metric {
                TextField("175", text: $heightCmText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text("cm").foregroundStyle(.secondary)
            } else {
                TextField("5", text: $heightFeetText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 36)
                Text("ft").foregroundStyle(.secondary)
                TextField("9", text: $heightInchesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 36)
                Text("in").foregroundStyle(.secondary)
            }
        }
    }

    private var weightRow: some View {
        HStack {
            Text("Weight")
            Spacer()
            TextField("0", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(profile.unitSystem.weightUnit).foregroundStyle(.secondary)
        }
    }

    private var bodyFatStep: some View {
        VStack(spacing: 16) {
            Text("Body fat % (optional)").font(.title2.bold())
            Text("If you have not measured your body fat with an accurate medical device, skip this step. You can always update this later.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Toggle("I know my exact body fat %", isOn: $trackBodyFat.animation())
            if trackBodyFat {
                SliderFieldCard(title: "Body fat", unit: "%", text: $bodyFatText, range: 3...60, step: 0.5)
            }
        }
        .onChange(of: trackBodyFat) { _, isOn in
            if isOn && Double(bodyFatText) == nil { bodyFatText = "20.0" }
        }
    }

    private var goalStep: some View {
        VStack(spacing: 16) {
            Text("What's your goal?").font(.title2.bold())
            ForEach(TrainingGoal.allCases) { goal in
                SelectableRow(title: goal.label, isSelected: profile.trainingGoal == goal) {
                    profile.trainingGoal = goal
                    switch goal {
                    case .cut where profile.weeklyRateKg >= 0:
                        profile.weeklyRateKg = UnitConversion.lbToKg(-1)
                    case .bulk where profile.weeklyRateKg <= 0:
                        profile.weeklyRateKg = UnitConversion.lbToKg(0.5)
                    default:
                        break
                    }
                }
            }
            if profile.trainingGoal != .recomp {
                HStack {
                    Text("Goal weight")
                    Spacer()
                    TextField("0", text: $goalWeightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text(profile.unitSystem.weightUnit).foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.themeCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var recompFocusStep: some View {
        VStack(spacing: 16) {
            Text("Recomp focus").font(.title2.bold())
            Text("Body recomposition doesn't follow one calorie direction — pick what fits you right now.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ForEach(RecompFocus.allCases) { focus in
                SelectableRow(title: focus.label, isSelected: profile.recompFocus == focus) {
                    profile.recompFocus = focus
                }
            }
        }
    }

    private var rateStep: some View {
        VStack(spacing: 16) {
            Text("How fast?").font(.title2.bold())
            Text(profile.unitSystem == .metric
                 ? "\(abs(profile.weeklyRateKg), specifier: "%.2f") kg per week"
                 : "\(abs(profile.weeklyRateLb), specifier: "%.1f") lbs per week")
                .font(.title3.bold())
            Slider(
                value: Binding(
                    get: { profile.weeklyRateLb },
                    set: { profile.weeklyRateKg = UnitConversion.lbToKg($0) }
                ),
                in: profile.trainingGoal == .cut ? -2.0...(-0.2) : 0.2...1.5,
                step: 0.1
            )
            Text(profile.trainingGoal == .cut ? "Slower is easier to sustain and preserves muscle." : "Slower minimizes fat gain while bulking.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var stepsStep: some View {
        VStack(spacing: 16) {
            Text("How many steps do you average each day?").font(.title2.bold())
            Text("This estimates the calories you burn just moving through your day, separate from workouts.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ForEach(StepsTier.allCases) { tier in
                SelectableRow(title: tier.label, isSelected: profile.stepsTier == tier) {
                    profile.stepsTier = tier
                }
            }
        }
    }

    private var workoutHoursStep: some View {
        VStack(spacing: 16) {
            Text("How many hours do you work out each week?").font(.title2.bold())
            Text("This estimates the calories you burn from formal exercise, on top of daily steps.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ForEach(WorkoutHoursTier.allCases) { tier in
                SelectableRow(title: tier.label, isSelected: profile.workoutHoursTier == tier) {
                    profile.workoutHoursTier = tier
                }
            }
        }
    }

    private var dietStep: some View {
        VStack(spacing: 16) {
            Text("Diet preference?").font(.title2.bold())
            Text("This shapes your protein/carb/fat targets.")
                .font(.themeSubheadline).foregroundStyle(.secondary)
            ForEach(DietPreference.allCases) { diet in
                SelectableRow(title: diet.label, isSelected: profile.dietPreference == diet) {
                    profile.dietPreference = diet
                }
            }
        }
    }

    private var summaryStep: some View {
        let calories = profile.calorieTarget(currentWeightKg: profile.startingWeightKg)
        let macros = profile.macroTargets(currentWeightKg: profile.startingWeightKg)
        return VStack(spacing: 20) {
            Text("Your daily targets").font(.title2.bold())
            VStack(spacing: 12) {
                Text("\(calories)").font(.system(size: 48, weight: .bold, design: .rounded))
                Text("calories / day").foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                MacroSummaryPill(label: "Protein", value: macros.protein, color: .themeProtein)
                MacroSummaryPill(label: "Carbs", value: macros.carbs, color: .themeCarbs)
                MacroSummaryPill(label: "Fat", value: macros.fat, color: .themeFat)
                MacroSummaryPill(label: "Fiber", value: profile.fiberTarget(currentWeightKg: profile.startingWeightKg), color: .themeFiber)
            }
        }
    }
    
    private var aiSetupStep: some View {
        AISetupFormView()
    }

    // MARK: - Logic

    private var canAdvance: Bool {
        switch resolvedStep {
        case .heightWeight:
            let heightValid = profile.unitSystem == .metric
                ? Double(heightCmText) != nil
                : Int(heightFeetText) != nil && Int(heightInchesText) != nil
            return heightValid && Double(weightText) != nil
        case .bodyFat:
            return !trackBodyFat || Double(bodyFatText) != nil
        case .goal:
            return profile.trainingGoal == .recomp || Double(goalWeightText) != nil
        default:
            return true
        }
    }

    private func advance() {
        switch resolvedStep {
        case .heightWeight:
            if profile.unitSystem == .metric {
                if let cm = Double(heightCmText) { profile.heightCm = cm }
            } else {
                let feet = Double(heightFeetText) ?? 5
                let inches = Double(heightInchesText) ?? 8
                profile.heightCm = UnitConversion.inchesToCm(feet * 12 + inches)
            }
            if let w = Double(weightText) { profile.startingWeightKg = profile.weightKg(fromDisplay: w) }
        case .bodyFat:
            profile.bodyFatPercent = trackBodyFat ? Double(bodyFatText) : nil
        case .goal:
            if profile.trainingGoal == .recomp {
                profile.goalWeightKg = profile.startingWeightKg
            } else if let gw = Double(goalWeightText) {
                profile.goalWeightKg = profile.weightKg(fromDisplay: gw)
            }
        default:
            break
        }

        if isLastStep {
            finish()
        } else {
            step += 1
        }
    }

    private func finish() {
        profile.hasCompletedOnboarding = true
        modelContext.insert(WeightEntry(weightKg: profile.startingWeightKg))
        try? modelContext.save()
    }
}

private struct SelectableRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        // Wrapped in a closure (rather than passing `action` directly) so Xcode
        // Previews' design-time instrumentation compiles without ambiguity.
        Button(action: { action() }) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.themeCard)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

/// Themed card pairing a slider with a manual entry field; the text is the single
/// source of truth, so typing moves the slider and sliding rewrites the text.
private struct SliderFieldCard: View {
    let title: String
    let unit: String
    @Binding var text: String
    let range: ClosedRange<Double>
    var step: Double = 1

    private var sliderValue: Binding<Double> {
        Binding(
            get: { min(max(Double(text) ?? range.lowerBound, range.lowerBound), range.upperBound) },
            set: { text = String(format: step < 1 ? "%.1f" : "%.0f", $0) }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                TextField("0", text: $text)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                Text(unit).foregroundStyle(.secondary)
            }
            Slider(value: sliderValue, in: range, step: step)
        }
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacroSummaryPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)g").font(.headline).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: UserProfile.self, WeightEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let profile = UserProfile()
    let _ = container.mainContext.insert(profile)
    OnboardingFlowView(profile: profile)
        .modelContainer(container)
}
#Preview("Height & Weight") {
    let container = try! ModelContainer(
        for: UserProfile.self, WeightEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let profile = UserProfile()
    let _ = container.mainContext.insert(profile)
    OnboardingFlowView(profile: profile, startStep: 2)
        .modelContainer(container)
}

