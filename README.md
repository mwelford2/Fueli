# Fueli

Fueli is a calorie and nutrition tracking app for iOS. It lets you log meals in whatever way is most convenient — snap a photo, scan a barcode, describe what you ate, or enter it manually — and uses AI to estimate nutrition when a database lookup isn't enough.

## Features

- **Photo logging** — photograph a meal and get an AI-estimated nutrition breakdown
- **Barcode scanning** — scan packaged foods for instant nutrition data
- **Describe a meal** — type a description and let AI estimate the macros
- **Manual entry** — enter calories and macros yourself
- **Saved meals** — save frequently eaten meals for quick re-logging
- **Workout logging** — log workouts and earn back calories burned
- **Step tracking** — pedometer integration shows daily steps and calories burned
- **Macro tracking** — daily targets for protein, carbs, fat, and fiber with ring visualisations
- **Water tracking** — log water intake toward a daily goal
- **Calorie rollover** — yesterday's overage or surplus adjusts today's budget automatically
- **Streaks & milestones** — logging streaks and achievement tracking
- **History view** — browse past days' logs

## Installation via SideStore / AltStore

Add the following source URL in SideStore or AltStore:

```
https://raw.githubusercontent.com/mwelford2/Fueli/main/apps.json
```

## Building from Source

Requirements: Xcode 16+, iOS 18+ deployment target, an Apple Developer account (free tier works for personal use).

```bash
# Generate the Xcode project from the spec
xcodegen generate

# Then open CalClone.xcodeproj in Xcode, set your team, and build/run.
```

---

## AI Usage

Claude (Anthropic) was used during development to automate menial coding tasks and research — things like writing boilerplate Swift views, looking up API behaviour, and debugging build errors. It was also used to set up this GitHub repository, create the release pipeline (`release.sh`), and generate the SideStore/AltStore source file (`apps.json`). All product decisions, architecture, and code review were done by the developer.
