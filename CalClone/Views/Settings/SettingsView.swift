import SwiftUI

struct SettingsView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        Label("AI Provider", systemImage: "sparkles")
                    }
                    NavigationLink {
                        ProfileSettingsView(profile: profile)
                    } label: {
                        Label("Goals & Profile", systemImage: "person.fill")
                    }
                }

                Section {
                    Picker(selection: $profile.unitSystem) {
                        ForEach(UnitSystem.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Units", systemImage: "ruler")
                    }
                    Toggle(isOn: $profile.rolloverExcessCalories) {
                        Label("Balance yesterday's overage", systemImage: "arrow.uturn.down.circle")
                    }
                    Stepper(value: $profile.dailyWaterTargetOz, in: 16...170, step: 8) {
                        Label("Water goal: \(waterGoalLabel)", systemImage: "drop.fill")
                    }
                } header: {
                    Text("Preferences")
                } footer: {
                    Text("When you go over budget, tomorrow's budget is trimmed by the overage — capped at 15% so one big day never causes harsh restriction.")
                }

                Section {
                    Text("Fueli stores all your data on-device. AI requests are sent only to the provider you configure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .themedScreenBackground()
            .navigationTitle("Settings")
        }
    }

    private var waterGoalLabel: String {
        profile.unitSystem == .metric
            ? "\(Int(UnitConversion.ozToMl(Double(profile.dailyWaterTargetOz)).rounded())) ml"
            : "\(profile.dailyWaterTargetOz) oz"
    }
}
