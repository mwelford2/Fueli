import SwiftUI

/// A lightweight confetti burst in the app's earthy palette, drawn with Canvas.
/// Increment `trigger` to fire a burst; the overlay never intercepts touches.
struct ConfettiBurstView: View {
    let trigger: Int

    @State private var burstDate: Date?

    private static let colors: [Color] = [
        .themeOlive, .themeSage, .themeCarbs, .themeProtein, .themeWater, .themeMist
    ]
    private static let particleCount = 90
    private static let duration: TimeInterval = 2.6
    private static let gravity: Double = 620

    init(trigger: Int) {
        self.trigger = trigger
    }

    /// Preview support: renders the burst as if it started `elapsed` seconds ago.
    fileprivate init(previewElapsed elapsed: TimeInterval) {
        self.trigger = 0
        _burstDate = State(initialValue: Date().addingTimeInterval(-elapsed))
    }

    var body: some View {
        Group {
            if let burstDate {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let elapsed = timeline.date.timeIntervalSince(burstDate)
                        guard elapsed >= 0 && elapsed <= Self.duration else { return }
                        draw(in: context, size: size, time: elapsed)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .task(id: trigger) {
            guard trigger > 0 else { return }
            burstDate = Date()
            try? await Task.sleep(for: .seconds(Self.duration))
            burstDate = nil
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        // Seeded per burst so every frame lays out the same particles.
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(trigger)) &* 0x9E3779B97F4A7C15 &+ 1)
        let origin = CGPoint(x: size.width / 2, y: size.height * 0.4)
        let fadeStart = Self.duration * 0.7

        for _ in 0..<Self.particleCount {
            let vx = Double.random(in: -280...280, using: &rng)
            let vy = Double.random(in: -760...(-320), using: &rng)
            let spin = Double.random(in: 2...9, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            let width = Double.random(in: 6...11, using: &rng)
            let height = Double.random(in: 9...16, using: &rng)
            let color = Self.colors[Int.random(in: 0..<Self.colors.count, using: &rng)]
            let delay = Double.random(in: 0...0.15, using: &rng)

            let t = max(0, time - delay)
            let x = origin.x + vx * t
            let y = origin.y + vy * t + 0.5 * Self.gravity * t * t
            guard y < size.height + 20 else { continue }

            let fade = time > fadeStart
                ? max(0, 1 - (time - fadeStart) / (Self.duration - fadeStart))
                : 1.0
            // Squashing the height as the piece spins fakes a tumbling strip.
            let tumble = max(0.15, abs(cos(spin * t)))
            let rect = CGRect(x: -width / 2, y: -height * tumble / 2, width: width, height: height * tumble)
            let transform = CGAffineTransform(translationX: x, y: y).rotated(by: spin * t * 0.6)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 1.5).applying(transform),
                with: .color(color.opacity(fade))
            )
        }
    }
}

extension View {
    /// Overlays a themed confetti burst (with a success haptic) that fires
    /// whenever `trigger` increments.
    func confettiCelebration(trigger: Int) -> some View {
        overlay { ConfettiBurstView(trigger: trigger) }
            .sensoryFeedback(.success, trigger: trigger)
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#Preview {
    ZStack {
        Color.themeBackground.ignoresSafeArea()
        Text("Goal reached!").font(.title2.bold())
    }
    .confettiCelebration(trigger: 1)
}
#Preview("Mid-burst") {
    ZStack {
        Color.themeBackground.ignoresSafeArea()
        Text("Goal reached!").font(.title2.bold())
    }
    .overlay { ConfettiBurstView(previewElapsed: 0.9) }
}

