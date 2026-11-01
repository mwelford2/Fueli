import SwiftUI
import SwiftData

struct StreaksView: View {
    @Bindable var profile: UserProfile
    @Query(sort: \FoodLog.loggedAt, order: .reverse) private var allLogs: [FoodLog]

    private var loggedDays: Set<DateComponents> {
        let calendar = Calendar.current
        return Set(allLogs.map { calendar.dateComponents([.year, .month, .day], from: $0.loggedAt) })
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        var streak = 0
        var day = calendar.startOfDay(for: Date())
        while loggedDays.contains(calendar.dateComponents([.year, .month, .day], from: day)) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    private var milestones: [Milestone] {
        [
            Milestone(title: "First Log", icon: "flag.checkered", isUnlocked: !allLogs.isEmpty),
            Milestone(title: "3 Day Streak", icon: "flame", isUnlocked: currentStreak >= 3),
            Milestone(title: "7 Day Streak", icon: "flame.fill", isUnlocked: currentStreak >= 7),
            Milestone(title: "30 Day Streak", icon: "trophy.fill", isUnlocked: currentStreak >= 30),
            Milestone(title: "50 Meals Logged", icon: "fork.knife.circle.fill", isUnlocked: allLogs.count >= 50),
            Milestone(title: "100 Meals Logged", icon: "medal.fill", isUnlocked: allLogs.count >= 100)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(currentStreak > 0 ? .orange : .gray)
                        Text("\(currentStreak) Day\(currentStreak == 1 ? "" : "s")")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                        Text("current streak")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.themeCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(milestones) { milestone in
                            VStack(spacing: 8) {
                                Image(systemName: milestone.icon)
                                    .font(.title)
                                    .foregroundStyle(milestone.isUnlocked ? Color.accentColor : .gray.opacity(0.4))
                                Text(milestone.title)
                                    .font(.caption.bold())
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(milestone.isUnlocked ? .primary : .secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(Color.themeCard)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding()
            }
            .themedScreenBackground()
            .navigationTitle("Milestones")
        }
    }
}

private struct Milestone: Identifiable {
    let title: String
    let icon: String
    let isUnlocked: Bool
    var id: String { title }
}
