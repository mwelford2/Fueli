import SwiftUI

/// The sheet shown when the user taps the "+" log button — mirrors CalAI's entry hub
/// (camera, barcode, describe, saved meals, manual entry).
struct LogEntryHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var route: Route?

    private enum Route: Identifiable {
        case camera, barcode, describe, manual, saved, workout
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HubOption(icon: "camera.fill", title: "Take a Photo", subtitle: "Let AI identify your food and estimate nutrition") {
                    route = .camera
                }
                HubOption(icon: "barcode.viewfinder", title: "Scan a Barcode", subtitle: "Look up packaged food instantly") {
                    route = .barcode
                }
                HubOption(icon: "text.bubble.fill", title: "Describe a Meal", subtitle: "Type what you ate and let AI estimate it") {
                    route = .describe
                }
                HubOption(icon: "star.fill", title: "Saved Meals", subtitle: "Quickly re-log a favorite") {
                    route = .saved
                }
                HubOption(icon: "square.and.pencil", title: "Enter Manually", subtitle: "Type in exact calories and macros") {
                    route = .manual
                }
                HubOption(icon: "figure.run", title: "Log a Workout", subtitle: "Track steps and calories burned automatically") {
                    route = .workout
                }
                Spacer()
            }
            .padding()
            .background(Color.themeBackground.ignoresSafeArea())
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(item: $route) { r in
                switch r {
                case .camera:
                    PhotoCaptureFlowView(onFinished: { dismiss() })
                case .barcode:
                    BarcodeScanFlowView(onFinished: { dismiss() })
                case .describe:
                    DescribeMealFlowView(onFinished: { dismiss() })
                case .manual:
                    ManualEntryView(onFinished: { dismiss() })
                case .saved:
                    SavedMealsFlowView(onFinished: { dismiss() })
                case .workout:
                    WorkoutLoggingView(onFinished: { dismiss() })
                }
            }
        }
    }
}

private struct HubOption: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color.themeCard)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
