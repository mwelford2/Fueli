import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Bindable var profile: UserProfile

    @Query(sort: \WeightEntry.recordedAt) private var weightEntries: [WeightEntry]
    @Query(sort: \FoodLog.loggedAt, order: .reverse) private var allLogs: [FoodLog]
    @Environment(\.modelContext) private var modelContext

    @State private var showAddWeight = false
    @State private var newWeightText = ""

    private var recentWeights: [WeightEntry] {
        Array(weightEntries.suffix(30))
    }

    private var weightUnit: String { profile.unitSystem.weightUnit }

    private var last7DaysCalories: [(day: Date, calories: Int)] {
        let calendar = Calendar.current
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: Date()))!
            let total = allLogs.filter { calendar.isDate($0.loggedAt, inSameDayAs: day) }.reduce(0) { $0 + $1.calories }
            return (day, total)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last 7 Days").font(.headline)
                        Chart(last7DaysCalories, id: \.day) { entry in
                            BarMark(
                                x: .value("Day", entry.day, unit: .day),
                                y: .value("Calories", entry.calories)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 160)
                    }
                    .padding()
                    .background(Color.themeCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Weight Trend").font(.headline)
                            Spacer()
                            Button("Add Weight") { showAddWeight = true }
                                .font(.caption)
                        }
                        if recentWeights.count >= 2 {
                            Chart(recentWeights) { entry in
                                LineMark(
                                    x: .value("Date", entry.recordedAt, unit: .day),
                                    y: .value("Weight", profile.displayWeight(entry.weightKg))
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(Color.accentColor)
                                PointMark(
                                    x: .value("Date", entry.recordedAt, unit: .day),
                                    y: .value("Weight", profile.displayWeight(entry.weightKg))
                                )
                                .foregroundStyle(Color.accentColor)
                            }
                            .frame(height: 160)
                        } else {
                            Text("Log at least two weigh-ins to see a trend.")
                                .font(.themeSubheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        }
                    }
                    .padding()
                    .background(Color.themeCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("All Logs").font(.headline)
                        ForEach(allLogs.prefix(50)) { log in
                            FoodLogRow(log: log)
                            Divider()
                        }
                    }
                    .padding()
                    .background(Color.themeCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .themedScreenBackground()
            .navigationTitle("History")
            .alert("Log Weight", isPresented: $showAddWeight) {
                TextField("Weight (\(weightUnit))", text: $newWeightText).keyboardType(.decimalPad)
                Button("Save") {
                    if let value = Double(newWeightText) {
                        let kg = profile.weightKg(fromDisplay: value)
                        modelContext.insert(WeightEntry(weightKg: kg))
                        try? modelContext.save()
                    }
                    newWeightText = ""
                }
                Button("Cancel", role: .cancel) { newWeightText = "" }
            }
        }
    }
}
