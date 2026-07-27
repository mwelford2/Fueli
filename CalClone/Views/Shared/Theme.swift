import SwiftUI
import UIKit

/// Earthy palette from the "AI Food Scanner App" reference design:
/// deep olive primary, sage support, mist surfaces, warm cream backgrounds.
extension Color {
    /// #354B04 — deep olive, the primary brand/action color.
    static let themeOlive = Color(red: 53/255, green: 75/255, blue: 4/255)
    /// #96AA83 — supporting sage green.
    static let themeSage = Color(red: 150/255, green: 170/255, blue: 131/255)
    /// #CFDEDA — pale mist green.
    static let themeMist = Color(red: 207/255, green: 222/255, blue: 218/255)
    /// #31382D — dark olive ink.
    static let themeInk = Color(red: 49/255, green: 56/255, blue: 45/255)

    /// Warm cream screen background (olive-charcoal in dark mode).
    static let themeBackground = dynamic(
        light: UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.09, green: 0.10, blue: 0.08, alpha: 1)
    )
    /// Card surface that sits on the cream background.
    static let themeCard = dynamic(
        light: .white,
        dark: UIColor(red: 0.15, green: 0.17, blue: 0.13, alpha: 1)
    )
    /// Track/placeholder tint behind progress rings and photo thumbnails.
    static let themeTrack = dynamic(
        light: UIColor(red: 0.88, green: 0.90, blue: 0.85, alpha: 1),
        dark: UIColor(red: 0.22, green: 0.25, blue: 0.20, alpha: 1)
    )

    // Data visualization — earthy tones that stay distinguishable.
    /// Protein — muted terracotta.
    static let themeProtein = Color(red: 178/255, green: 89/255, blue: 62/255)
    /// Carbs — honey amber.
    static let themeCarbs = Color(red: 201/255, green: 155/255, blue: 63/255)
    /// Fat — sage green.
    static let themeFat = Color(red: 150/255, green: 170/255, blue: 131/255)
    /// Fiber — warm bark brown.
    static let themeFiber = Color(red: 138/255, green: 109/255, blue: 69/255)
    /// Water — desaturated teal drawn from the mist tone.
    static let themeWater = Color(red: 94/255, green: 142/255, blue: 140/255)

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

extension Font {
    /// App-wide subheadline: one notch larger than the system subheadline
    /// (16pt callout vs 15pt), still scaling with Dynamic Type.
    static let themeSubheadline: Font = .callout
}

extension View {
    /// Replaces the default system background of a screen's scroll container
    /// (ScrollView, List, or Form) with the themed cream background.
    func themedScreenBackground() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Color.themeBackground.ignoresSafeArea())
    }
}
