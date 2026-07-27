import SwiftUI

private enum AppTab: Hashable {
    case today, history, log, streaks, settings
}

struct MainTabView: View {
    @Bindable var profile: UserProfile
    @State private var selection: AppTab = .today
    @State private var showLogSheet = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "house.fill", value: AppTab.today) {
                DashboardView(showLogSheet: $showLogSheet)
            }
            Tab("History", systemImage: "calendar", value: AppTab.history) {
                HistoryView(profile: profile)
            }
            Tab("Log", systemImage: "plus.circle.fill", value: AppTab.log) {
                Color.clear
            }
            Tab("Streaks", systemImage: "flame.fill", value: AppTab.streaks) {
                StreaksView(profile: profile)
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                SettingsView(profile: profile)
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .log {
                showLogSheet = true
                selection = .today
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogEntryHubView()
        }
    }
}
