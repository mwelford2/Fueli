# Fueli

Fueli is a native SwiftUI nutrition tracker for iOS 18 and later. Food history and My Foods stay in a local SwiftData store.

## Logging and My Foods

- Photo analysis shows an editable AI description. USDA can use a separate AI query-planning call; matched database records and user-corrected quantities determine nutrition.
- Photo and Describe Meal share a **USDA / Open Food Facts** database choice after reviewing the AI description, ingredient names, preparation, brands and weights. Open Food Facts is a free, keyless packaged-food alternative; each product must be explicitly selected and confirmed. It does not receive photos or use another AI query-planning call.
- Describe Meal also supports **Enter ingredients without AI**. Separate foods with new lines, semicolons or “with”, review the split, and supply weights. Counts/household portions are not guessed; compound names such as “mac and cheese” remain intact.
- Barcode lookup checks My Foods, Open Food Facts API v3, and exact-GTIN USDA branded matches. Invalid checksums, missing nutrition, ambiguous matches, and source conflicts require review.
- Describe Meal and manual entry use the shared confirmation flow.
- Ingredient review labels estimated weights in grams. USDA lookup checks 50 candidates, handles bagel/bagels, and can use another defensible record when a preferred record lacks required nutrients. Broader ingredient/preparation matches require your explicit choice; connection and key errors remain distinct from no suitable match.

See [ingredient lookup investigation and tests](Fueli/MEAL_LOOKUP_FIX.md) for the bagel/cream-cheese regression and live-test limitation.
See [database-choice research and verification](Fueli/DATABASE_LOOKUP_RESEARCH.md) for the FatSecret free-tier/authentication/storage findings, alternative selection, query cleaning, tests and setup.
- **Log Food** logs the selected fractional quantity. **Save to My Foods** saves exactly one defined standard serving and creates no consumption log.
- My Foods supports search, favorites, recent/frequent foods, editing, confirmed deletion, and quantity selection before logging.
- Create Meal combines saved-food ingredient snapshots deterministically. Recipes retain editable quantities and can be logged with a multiplier.
- Scan Receipt uses on-device Apple document capture and Vision OCR. Review and explicitly select products before importing them into My Foods. Receipt text and images are not sent to AI, and imports never log food consumption.
- Local versioned JSON backup exports/restores foods, recipes and historical food logs, with optional photos. Restore validates content, adds missing records, and skips duplicates.

Calories and macros retain Double precision for new calculations and snapshots; rounding occurs for display. Original integer calorie fields remain as a migration fallback. Mass and volume conversions require known item-specific serving definitions; the app never assumes density.

Workout logging, water, macro goals, history, streaks and calorie rollover remain available. The daily activity card now displays Apple Health active energy instead of a step count.

## Apple Health and fitness apps

Setup and Settings → Goals & Profile let you enter **Average Daily Burn** manually, including resting energy and all activity. Tap **Use This Daily Burn** to apply it; the preview shows the goal adjustment and calories to eat. Manual burn takes priority over a saved Health average, and setup skips step/workout questions. A manual food-intake override remains separate and takes priority until disabled.

Connect Active Energy for the dashboard. Setup/Goals can import a maintenance baseline from active + resting energy over the previous 14 completed days, requiring at least seven paired days. A successful import replaces estimated maintenance and skips step/workout setup questions. Today's activity is not added to this baseline again. Manual targets remain fixed.

Empty results are distinct from failed queries; the app reports active/resting/paired-day counts. HealthKit intentionally does not reveal whether read permission was denied. Review permissions for **both Active Energy and Resting Energy** in Health if history is incomplete. Wearable energy remains an estimate; review weight trends after 2–4 weeks. See [clinical evidence and goal rules](Fueli/CALORIE_EVIDENCE.md).

Settings → Health Connections includes Garmin Connect, Google Health/Fitbit, Oura, WHOOP, Strava and other Health-compatible apps through their Apple Health sharing. This is a local HealthKit bridge; direct vendor OAuth is not implemented. Available metrics/history depend on each provider. See [provider setup and official references](Fueli/HEALTH_CONNECTIONS.md).

The selected local team's Fueli provisioning profile enables HealthKit. Use Debug/Release with an appropriate developer team and HealthKit-enabled App ID/profile on iPhone. The **Free** configuration explicitly disables HealthKit. Real permissions and vendor/Watch sync still require device verification.

## AI configuration

Configure an OpenAI-compatible or Anthropic endpoint, model and personal API key in Settings → AI Provider. Credentials remain in Keychain. Model capability discovery checks exact Hugging Face publisher metadata with documented Google/model-catalog fallbacks. **Use Anyway** presents a warning before saving an unconfirmed model. Published model support does not guarantee a gateway enables image inputs. See [model discovery](Fueli/MODEL_CAPABILITIES.md).

Provider requests use documented JSON Schema output settings, with a bounded fallback only for explicit unsupported-feature responses. Local decoding and quantity checks remain mandatory. Live provider tests are opt-in; ordinary tests use fixtures.

## Persistence and recovery

Versioned SwiftData migrations cover the original unversioned models, intermediate Health/library schemas, and version 2 library data. Version 3 adds optional precise calorie values; version 4 adds an optional manually entered total daily burn. Historical nutrition stays a snapshot when saved foods change. Store-opening failures retain the original store and show recovery guidance; Fueli never deletes history automatically.

Nutrition JSON backups include diet history, dates and notes; store them privately. Profile, weights, water and workouts remain in the app but are outside the nutrition export format. Import does not silently overwrite history.

## Build and test

Use Xcode 26 or newer for the current source, deploying to iOS 18+. Structured document recognition is gated to iOS 26; iOS 18 uses accurate Vision text recognition. Only an iOS 26.5 runtime was available for execution testing.

Open the checked-in Fueli.xcodeproj. Preserve/select your signing team. For USDA lookup in published releases, add your own free key in Settings → Food Database; it is stored in Keychain on your device. Public Release/Free builds exclude the developer’s bundled key. Copy Fueli/Secrets.example.xcconfig to Fueli/Secrets.xcconfig before building; the base configuration file must exist. Its key may remain blank when configuring USDA in-app. A local Debug key is an optional fallback. Do not commit credentials. An embedded client key is extractable; distributed production builds need an appropriately protected proxy/key-management strategy.

Optional project regeneration (requires XcodeGen):

```sh
xcodegen generate
```

The spec includes the application, unit-test target, OCR fixture, AI prompt, HealthKit entitlements and Free configuration. Re-select signing settings after regeneration if needed.

From the repository root, choose an installed simulator:

```sh
xcodebuild -project Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The latest checked-in-source verification passed 67 tests (68 executions including parameterized cases), one optional live AI test skipped, zero failures. A separate signed simulator build passed. Populated-store migrations, corrupt-store preservation, nutrition precision, backup round trips, model metadata, both OCR paths and mocked product-service errors are covered. Exact executed commands, result path, manual simulator checks, and remaining acceptance gaps are recorded in [OVERHAUL_STATUS.md](Fueli/OVERHAUL_STATUS.md). Local ReviewArtifacts contains the simulator screenshot bundle; it is excluded from public commits to avoid publishing profile-derived information.

Set FUELI_LIVE_AI_TESTS=1 only when intentionally running the credential-dependent provider test; it may send its test input to your configured provider.

## Reference data

USDA FoodData Central data is CC0. Open Food Facts database is ODbL, individual contents use the Database Contents License, and product images are CC BY-SA. Review share-alike requirements before redistributing derived databases. The OFF User-Agent identifies this application's real GitHub repository. Product-image downloading and exhaustive household-portion metadata are still incomplete; see the status report rather than assuming full acceptance.

## Installation via SideStore / AltStore

The published release source is:

```
https://raw.githubusercontent.com/mwelford2/Fueli/main/apps.json
```

Release v1.0.12 includes the nutrition/Health/manual-burn changes. Physical iPhone Health history, camera, and vendor sync still require the device checks in the status report.

## AI Usage

Claude (Anthropic) was used during development to automate menial coding tasks and research — things like writing boilerplate Swift views, looking up API behaviour, and debugging build errors. It was also used to set up this GitHub repository, create the release pipeline (`release.sh`), and generate the SideStore/AltStore source file (`apps.json`). All product decisions, architecture, and code review were done by the developer.

## Rigorous verification and conditional releases

See [the testing/release plan](Fueli/TESTING_RELEASE_PLAN.md) for primary comparable-app test sources, all-feature test layers, private live configuration, commands, device limitations and fail-closed publication requirements. Run `scripts/test_all.sh` with an installed simulator destination and the ignored local JSON configuration. This enables real AI text/photo/planning and USDA/Open Food Facts checks as well as deterministic tests and isolated UI journeys. UI test stores never open or erase the normal app store. Test photographs/OCR fixtures and HTTP mocks are excluded from Release.

`release.sh` requires passing evidence for the exact IPA and source; skipped or blocked checks do not count as passes. It verifies `com.welford.fueli` and rejects a bundled USDA credential. Camera and Apple Health acceptance was confirmed by the user; this does not establish universal device or clinical accuracy.

See the [1.0.14 verification report](Fueli/RIGOROUS_TEST_REPORT.md) for executed commands, measured results, corrected failures, builds and known limits.
