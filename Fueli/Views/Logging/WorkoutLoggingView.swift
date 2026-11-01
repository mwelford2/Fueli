import SwiftUI
import SwiftData

struct WorkoutLoggingView: View {
    let onFinished: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @State private var pedometer = PedometerService.shared
    @State private var flowStep: FlowStep = .pickType

    private var weightKg: Double { profiles.first?.startingWeightKg ?? 70.0 }

    var body: some View {
        NavigationStack {
            switch flowStep {
            case .pickType:
                WorkoutTypePickerView { type in
                    pedometer.startWorkoutSession()
                    flowStep = .active(type: type, startTime: Date())
                }
                .navigationTitle("Log Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onFinished() }
                    }
                }

            case .active(let type, let startTime):
                ActiveWorkoutView(
                    workoutType: type,
                    startTime: startTime,
                    steps: pedometer.workoutSteps,
                    distanceMeters: pedometer.workoutDistanceMeters,
                    weightKg: weightKg,
                    onFinish: { durationSeconds in
                        let (steps, distance) = pedometer.stopWorkoutSession()
                        let calories = PedometerService.workoutCalories(
                            met: type.met, weightKg: weightKg, durationSeconds: durationSeconds
                        )
                        flowStep = .summary(WorkoutResult(
                            type: type,
                            startedAt: startTime,
                            durationSeconds: durationSeconds,
                            steps: steps,
                            caloriesBurned: calories,
                            distanceMeters: distance
                        ))
                    },
                    onCancel: {
                        _ = pedometer.stopWorkoutSession()
                        onFinished()
                    }
                )

            case .summary(let result):
                WorkoutSummaryView(result: result) {
                    let log = WorkoutLog(
                        workoutType: result.type,
                        startedAt: result.startedAt,
                        durationSeconds: result.durationSeconds,
                        steps: result.steps,
                        caloriesBurned: result.caloriesBurned,
                        distanceMeters: result.distanceMeters
                    )
                    modelContext.insert(log)
                    try? modelContext.save()
                    onFinished()
                } onDiscard: {
                    onFinished()
                }
            }
        }
    }

    private enum FlowStep {
        case pickType
        case active(type: WorkoutType, startTime: Date)
        case summary(WorkoutResult)
    }
}

struct WorkoutResult {
    let type: WorkoutType
    let startedAt: Date
    let durationSeconds: Int
    let steps: Int
    let caloriesBurned: Int
    let distanceMeters: Double
}

// MARK: - Step 1: Pick workout type

private struct WorkoutTypePickerView: View {
    let onSelect: (WorkoutType) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(WorkoutType.allCases) { type in
                    Button { onSelect(type) } label: {
                        VStack(spacing: 12) {
                            Image(systemName: type.icon)
                                .font(.title)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                            Text(type.label)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Color.themeCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Color.themeBackground.ignoresSafeArea())
    }
}

// MARK: - Step 2: Active workout with live tracking

private struct ActiveWorkoutView: View {
    let workoutType: WorkoutType
    let startTime: Date
    let steps: Int
    let distanceMeters: Double
    let weightKg: Double
    let onFinish: (Int) -> Void
    let onCancel: () -> Void

    @State private var elapsedSeconds: Int = 0

    private var liveCalories: Int {
        PedometerService.workoutCalories(met: workoutType.met, weightKg: weightKg, durationSeconds: elapsedSeconds)
    }

    private var formattedDistance: String {
        distanceMeters >= 1000
            ? String(format: "%.2f km", distanceMeters / 1000)
            : String(format: "%.0f m", distanceMeters)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 8) {
                    Image(systemName: workoutType.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text(workoutType.label)
                        .font(.title2.bold())
                }
                .padding(.top, 20)

                Text(formatDuration(elapsedSeconds))
                    .font(.system(size: 64, weight: .bold, design: .monospaced))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    WorkoutStatCard(value: "\(liveCalories)", unit: "kcal", label: "Burned")
                    WorkoutStatCard(value: "\(steps)", unit: "steps", label: "Steps")
                    if distanceMeters > 0 {
                        WorkoutStatCard(value: formattedDistance, unit: "", label: "Distance")
                    }
                }

                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Button {
                        onFinish(elapsedSeconds)
                    } label: {
                        Label("Finish Workout", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button("Cancel Workout", role: .destructive, action: onCancel)
                        .font(.subheadline)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .background(Color.themeBackground.ignoresSafeArea())
        .navigationTitle("Active Workout")
        .navigationBarBackButtonHidden()
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }
}

private struct WorkoutStatCard: View {
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.title.bold())
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.themeCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Step 3: Summary and save

private struct WorkoutSummaryView: View {
    let result: WorkoutResult
    let onSave: () -> Void
    let onDiscard: () -> Void

    private var formattedDuration: String {
        let h = result.durationSeconds / 3600
        let m = (result.durationSeconds % 3600) / 60
        let s = result.durationSeconds % 60
        return h > 0
            ? String(format: "%d hr %02d min", h, m)
            : String(format: "%d min %02d sec", m, s)
    }

    private var formattedDistance: String? {
        guard result.distanceMeters > 0 else { return nil }
        return result.distanceMeters >= 1000
            ? String(format: "%.2f km", result.distanceMeters / 1000)
            : String(format: "%.0f m", result.distanceMeters)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: result.type.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Workout Complete!")
                        .font(.title2.bold())
                    Text(result.type.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(spacing: 16) {
                    WorkoutSummaryRow(icon: "clock.fill", label: "Duration", value: formattedDuration)
                    WorkoutSummaryRow(icon: "flame.fill", label: "Calories Burned", value: "\(result.caloriesBurned) kcal")
                    WorkoutSummaryRow(icon: "figure.walk", label: "Steps", value: "\(result.steps)")
                    if let distance = formattedDistance {
                        WorkoutSummaryRow(icon: "map.fill", label: "Distance", value: distance)
                    }
                }
                .padding()
                .background(Color.themeCard)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 12) {
                    Button(action: onSave) {
                        Text("Save Workout")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button("Discard", role: .destructive, action: onDiscard)
                        .font(.subheadline)
                }
            }
            .padding()
        }
        .background(Color.themeBackground.ignoresSafeArea())
        .navigationTitle("Summary")
        .navigationBarBackButtonHidden()
    }
}

private struct WorkoutSummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
