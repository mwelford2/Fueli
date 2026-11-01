import SwiftUI

struct SettingsView: View {
    @Bindable var profile: UserProfile

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("Food Database") { FoodDatabaseSettingsView() }
                    NavigationLink("Nutrition Backup") { NutritionBackupView() }
                    NavigationLink {
                        AIProviderSettingsView()
                    } label: {
                        Label("AI Provider", systemImage: "sparkles")
                    }
                    NavigationLink {
                        HealthConnectionsView(profile: profile)
                    } label: {
                        Label("Health Connections", systemImage: "heart.text.square")
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


/// All integrations use the user's local Apple Health store, not vendor credentials.
enum FitnessHealthApp: String, CaseIterable, Identifiable {
    case garmin, google, oura, whoop, strava, other
    var id: String { rawValue }
    var name: String {
        switch self {
        case .garmin: return "Garmin Connect"
        case .google: return "Google Health / Fitbit"
        case .oura: return "Oura"
        case .whoop: return "WHOOP"
        case .strava: return "Strava"
        case .other: return "Apple Watch & Other Health Apps"
        }
    }
    var instructions: String {
        switch self {
        case .garmin:
            return "In Garmin Connect, open More → Settings → Connected Apps → Apple Health. Enable the energy categories offered, then sync your Garmin device and open Garmin Connect. Check Active Energy and Resting Energy in Apple Health to see what was written."
        case .google:
            return "In Google Health, open Connections → Partner apps (or Apps and services) → Apple Health. Enable the sharing options offered and sync your device. Menu names and exported metrics vary by version. Verify Active Energy and Resting Energy in Apple Health; workout records alone are not a full-day calorie total. Android Health Connect cannot be read directly on this iPhone."
        case .oura:
            return "In Oura, enable Apple Health under Settings → Data Sharing. Allow Oura to write Active Energy, then sync your ring. Oura's active calories exclude resting energy; Fueli also needs readable resting calories to calculate a total-energy baseline."
        case .whoop:
            return "In WHOOP, open More → App Settings → Integrations → Apple Health, connect, and allow sharing Active Energy. Sync your device. WHOOP's shared active energy is not a complete daily burn; readable resting energy is also required."
        case .strava:
            return "In Strava, open Settings → Manage Apps and Devices → Health and enable Send to Health. Allow the offered permissions. Strava workout calories cover activities, not all-day resting energy. Avoid importing the same activity through several apps."
        case .other:
            return "For Apple Watch, sync it with the iPhone Health app. For another fitness app, enable its Apple Health sharing and allow writing energy data. In Health, open Active Energy and Resting Energy → Data Sources & Access to inspect sources and their priority. Fueli reads shared calories from compatible sources without a separate vendor login."
        }
    }
    var helpURL: URL {
        let address: String
        switch self {
        case .garmin: address = "https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA"
        case .google: address = "https://support.google.com/googlehealth/answer/14236613?hl=en"
        case .oura: address = "https://ouraring.com/blog/apple-health/"
        case .whoop: address = "https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US"
        case .strava: address = "https://support.strava.com/en-us/articles/15402024-apple-health-and-strava"
        case .other: address = "https://support.apple.com/en-us/108779"
        }
        return URL(string: address)!
    }
}

struct HealthConnectionsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var health = HealthKitService.shared
    @State private var sources: [HealthKitService.EnergySource] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var didCheckSources = false

    var body: some View {
        Form {
            Section {
                Text("Connect your fitness app to Apple Health, then allow Fueli to read shared calories. No Garmin, Google, or other account password is needed in Fueli.")
                Button("Allow Fueli to Read Shared Calories") {
                    Task { await connect() }
                }.disabled(isLoading || !health.isAvailable)
                if !health.isAvailable { Text("Apple Health is unavailable on this device.").foregroundStyle(.secondary) }
            } header: { Text("Connect through Apple Health") }

            Section("Fitness Apps") {
                ForEach(FitnessHealthApp.allCases) { app in
                    NavigationLink {
                        Form {
                            Section("Set up " + app.name) { Text(app.instructions) }
                            Section {
                                Button("Allow Fueli to Read Shared Calories") { Task { await connect() } }
                                    .disabled(isLoading || !health.isAvailable)
                                Link("Official setup guide", destination: app.helpURL)
                                if let message { Text(message).font(.caption) }
                            }
                            Section {
                                Text("This connects through Apple Health. It does not sign Fueli into your vendor account. The metrics a provider exports can vary; check the observed sources on the previous screen after syncing.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.navigationTitle(app.name).navigationBarTitleDisplayMode(.inline)
                    } label: { Label(app.name, systemImage: "heart.circle") }
                }
            }

            Section {
                if isLoading { ProgressView("Checking shared Health data…") }
                ForEach(sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.name)
                        Text(source.dataDescription).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if didCheckSources && sources.isEmpty {
                    Text("No readable energy sources found in the last 14 days. Sync your fitness app, enable its Health write permissions, and allow Fueli to read Active and Resting Energy. Health does not disclose whether read access was denied.")
                        .font(.caption)
                }
                Button("Refresh Shared Sources") { Task { await refreshSources() } }
                    .disabled(isLoading || !health.isAvailable)
            } header: { Text("Observed Energy Sources") }
              footer: { Text("Sources indicate readable recent data, not live account connection status. Apple Health merges sources; Fueli does not add vendor totals on top of each other. Manage source priority in Health.") }

            Section("Calorie Plan") {
                if profile.hasManualMaintenance {
                    Text("Your plan currently uses a manually entered total daily burn. A successful baseline update switches it to Apple Health.").font(.caption)
                }
                if profile.hasHealthMaintenance {
                    LabeledContent("Saved total-energy average", value: "\(Int(profile.healthMaintenanceCalories!.rounded())) kcal/day")
                }
                Button("Update Baseline from Shared Data") { Task { await updateBaseline() } }
                    .disabled(isLoading || !health.isAvailable)
                Text("Requires at least 7 eligible completed days of active + resting energy in the last 14 days. Active-only and workout-only apps may not supply enough data. Your existing baseline stays unchanged if data is insufficient.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption) }
            }
            Section("Manage or Disconnect") {
                Text("In Apple Health → profile → Apps → Fueli, change read permissions. To stop a fitness app sharing, change that app's Health write permissions. Disconnecting does not delete existing Health data or Fueli's saved baseline; switch to activity estimates in Goals & Profile to stop using it.")
                    .font(.caption)
                Link("Manage Health apps and data sources", destination: FitnessHealthApp.other.helpURL)
            }
        }
        .navigationTitle("Health Connections")
        .task {
            if health.hasRequestedActiveEnergy { await refreshSources() }
        }
        .refreshable { await refreshSources() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && health.hasRequestedActiveEnergy { Task { await refreshSources() } }
        }
    }

    @MainActor private func connect() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await health.connectTotalEnergy()
            sources = try await health.recentEnergySources()
            didCheckSources = true
            message = "Health permission request completed. Sync your fitness app and inspect observed sources; access to each data type is controlled in Health."
        } catch { message = "Couldn’t connect to Apple Health: " + error.localizedDescription }
    }

    @MainActor private func refreshSources() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await health.recentEnergySources()
            didCheckSources = true
            message = nil
        } catch { sources = []; message = "Couldn’t read shared sources. Retry after checking Health access. " + error.localizedDescription }
    }

    @MainActor private func updateBaseline() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await health.connectTotalEnergy()
            guard let average = try await health.averageTotalEnergy() else {
                message = health.historySummary + " Your existing plan is unchanged."
                return
            }
            let old = (profile.manualMaintenanceCalories, profile.healthMaintenanceCalories, profile.healthEnergyDayCount, profile.healthEnergyWindowStart, profile.healthEnergyWindowEnd)
            profile.manualMaintenanceCalories = nil
            profile.healthMaintenanceCalories = average.calories
            profile.healthEnergyDayCount = average.days
            profile.healthEnergyWindowStart = average.start
            profile.healthEnergyWindowEnd = average.end
            do { try modelContext.save() } catch {
                (profile.manualMaintenanceCalories, profile.healthMaintenanceCalories, profile.healthEnergyDayCount, profile.healthEnergyWindowStart, profile.healthEnergyWindowEnd) = old
                throw error
            }
            message = "Updated using \(average.days) eligible days of shared active + resting calories."
        } catch { message = "Couldn’t update the baseline: " + error.localizedDescription }
    }
}


struct FoodDatabaseSettingsView: View {
    @State private var keyText = ""
    @State private var hasPersonalKey = false
    @State private var message: String?
    @State private var confirmingRemoval = false
    @FocusState private var keyFocused: Bool
    private var validKey: String { USDAapiCaller.resolveAPIKey(userKey: keyText, bundledKey: nil) }

    var body: some View {
        Form {
            Section("USDA FoodData Central") {
                Text("Photo, described-meal and receipt ingredient lookups use USDA records. Public Fueli releases do not include a shared personal API key.").font(.caption)
                Text(hasPersonalKey ? "Personal USDA key configured on this device" : "Add your own USDA API key for lookups")
                SecureField("USDA API Key", text: $keyText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($keyFocused)
                    .accessibilityLabel("Personal USDA FoodData Central API key")
                Button("Save USDA Key") {
                    do {
                        try KeychainStore.saveChecked(validKey, account: USDAapiCaller.personalKeyAccount)
                        hasPersonalKey = true; keyText = ""; keyFocused = false
                        message = "USDA key saved securely on this device."
                        Task { await BarcodeLookupService.shared.clearCache() }
                    } catch { message = "Could not save the key: " + error.localizedDescription }
                }.disabled(validKey.isEmpty)
                if hasPersonalKey {
                    Button("Remove Personal USDA Key", role: .destructive) { confirmingRemoval = true }
                }
                Link("Get a free USDA API key", destination: URL(string: "https://fdc.nal.usda.gov/api-key-signup/")!)
                Text("Your key is stored in Keychain and sent only with your USDA lookup requests. It is not included in nutrition exports. A locally configured development-build key is a fallback; client-embedded keys are extractable.").font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption) }
            }
            Section("Data sources") {
                Text("USDA FoodData Central: public-domain reference data. Open Food Facts: ODbL database; individual contents use the Database Contents License and images CC BY-SA. Review matches and portions before logging.").font(.caption)
                Link("USDA API documentation", destination: URL(string: "https://fdc.nal.usda.gov/api-guide/")!)
                Link("Open Food Facts data and licenses", destination: URL(string: "https://world.openfoodfacts.org/data")!)
            }
        }.themedScreenBackground().navigationTitle("Food Database")
            .onAppear { hasPersonalKey = !(KeychainStore.read(account: USDAapiCaller.personalKeyAccount) ?? "").isEmpty }
            .confirmationDialog("Remove the personal USDA key from this device?", isPresented: $confirmingRemoval) {
                Button("Remove Key", role: .destructive) {
                    do {
                        try KeychainStore.deleteChecked(account: USDAapiCaller.personalKeyAccount)
                        hasPersonalKey = false; message = "Personal key removed."
                        Task { await BarcodeLookupService.shared.clearCache() }
                    } catch { message = "Could not remove the key: " + error.localizedDescription }
                }
            }
    }
}
