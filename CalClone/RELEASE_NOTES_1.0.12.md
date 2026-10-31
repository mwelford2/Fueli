# Fueli 1.0.12

- Enter average total daily calorie burn in setup or Goals & Profile, including resting energy and all activity. Preview calories to eat for your goal; a manual average skips step/workout questions.
- Read active/resting energy from Apple Health, with clearer empty-history feedback and safer total-energy averaging. Fitness-app setup guides use Apple Health sharing.
- Correct Gemma vision capability discovery using publisher metadata, with a Use Anyway warning for unconfirmed models.
- Add My Foods search, favorites/recent/frequent browsing, fractional serving selection, separate Log Food and Save actions, and reusable meals with deterministic ingredient calculations.
- Improve barcode validation, exact database matching, carbohydrate/energy normalization, source conflict handling, caching and rate-limit behavior.
- Split photo description/review from USDA query planning. Receipt capture and OCR run on-device; reviewed imports save foods without logging consumption.
- Add versioned local nutrition JSON export/restore and non-destructive SwiftData migrations preserving existing history and favorites.

## Setup and compatibility

- iOS 18 or later. Structured document OCR is available on iOS 26, with accurate text OCR fallback.
- Add your own USDA FoodData Central key under Settings → Food Database. It is saved in Keychain; the public IPA does not embed the developer's personal key. Configure your AI provider separately.
- This is a signed sideloading IPA, not an App Store installation. Re-sign/install with the appropriate developer capabilities; HealthKit requires a HealthKit-enabled provisioning profile.
- Existing history is retained on upgrade. Nutrition backups cover foods, recipes and meal history; they do not include profile, weight, water or workouts.

## Verification and limits

Release archive succeeded. The simulator suite passed 67 tests (68 passing executions including parameterized cases), with one optional live AI test skipped and zero failures. Simulator builds/tests cover calculations, populated migrations, backup round trips, model metadata, local OCR and mocked product-service failures. Manual simulator checks covered setup/settings burn entry, separate save/log behavior, recipes, receipt review and Files export/import. Physical camera/Watch/vendor sync and live AI-provider responses still need device checks. Receipt overlap handling, exhaustive household portions and explicit unknown optional-nutrient presentation remain limited; see CalClone/OVERHAUL_STATUS.md.
