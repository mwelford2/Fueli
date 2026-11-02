# Fueli 1.0.14 verification

Status: all required final checks passed; candidate ready for publication. Earlier failed/interrupted runs are retained locally and are not counted as passes.

## Scope and design

- Deterministic tests cover GTIN corruption at every digit position, all UPC-E expansion branches/number systems, explicit format/length mismatches and leading zeros; nutrition precision, conversions, missing/zero values, conflicts, malformed responses, rate limits and no-suitable-match outcomes.
- Nutrient conservation spans 128 references × 6 multipliers. GTIN tests independently construct 100 examples for each supported retail length, then corrupt every digit. Goal tests exercise goal/diet/sex/body-weight/burn combinations, individual manual overrides and invalid/nonfinite extremes. These are software properties, not clinical validation.
- Persistence tests exercise independent save/log, one-standard-serving saving, repeated callbacks, disk-write rollback/retry, repeated intentional sessions, canonical duplicate rejection, immutable historical snapshots, recipe/backup metadata, corrupt imports and populated store reopening/migration.
- AI transport uses injected sessions/configuration/key providers. Fixtures verify each configured provider's authentication/image wire contract, structured-output compatibility fallback, errors and malformed replies. Required live tests use the user's private local configuration, including real image recognition of a licensed public banana photograph and a corrected 135.5 g USDA plan. No private meal/receipt image is used for live testing.
- Receipt tests run actual Apple structured-document OCR and accurate text OCR against a synthetic fixture, plus deterministic row/metadata/abbreviation/confidence/coordinate rules. UI import requires an explicit product selection and creates no consumption log. This is not a representative real-world receipt accuracy study; no population accuracy statistic is claimed.
- UI journeys use UUID-isolated Debug stores and deterministic HTTP responses, plus actual on-device receipt OCR. They exercise onboarding, all logging routes, manual invalid input, save/reopen/fractional log, library search/favorites/edit/delete, historical edit/delete, recipes, barcode/manual fallback, photo/text review and database choice, network failure/retry, offline saved foods, water/date isolation, manual burn settings, weight history, workouts, backup sheets, settings and milestones. Real API contracts are checked separately.

## Defects addressed during testing

- Explicit barcode formats could accept the wrong digit length; non-ASCII digits/checksum inputs were insufficiently constrained.
- Invalid workout/profile values could overflow integer conversion or produce inconsistent computed macro budgets. Partial macro overrides were previously ignored unless all three were present.
- Backup validation did not fully reject malformed historical recipe snapshots, empty ingredients and invalid dates before mutation.
- Confirmation actions lacked a shared persistence-session idempotency boundary. `NutritionCommitter` now independently guards save/log, preserves standard values and rolls back failed writes for retry. Large unlogged quantities no longer prevent saving a standard serving.
- Numeric serving replacement could retain an old digit. Nutrition value fields now select their contents on focus; the edit/save/history test passed three repeated runs before the complete rerun. A text editing buffer preserves fractional direct entry and round-trip Double precision; invalid text disables commitment. Manual and serving numeric keyboards have explicit dismissal controls. Onboarding content scrolls on compact displays.
- Receipt metadata matching could confuse CASHEWS with CASH and TOTAL GRAIN CEREAL with TOTAL. Register prefixes, invalid coordinates/confidence and image orientation are handled explicitly.
- Key replacement no longer deletes the previous credential before attempting a write. AI HTTP error messages do not echo private provider response bodies. Credential-bearing endpoint URLs are rejected.
- Generated Info.plist versions could revert to XcodeGen's 1.0 default. They now reference the configured marketing/build versions. Release publication checks exact source/version/bundle/IPA and refuses automatic deletion of an existing release.

## Persistence and sources

No new schema version or destructive recovery was introduced by this testing pass. Single-food log-only entries now preserve standard-serving/source/barcode metadata in the existing ingredient snapshot payload. Its additional barcode property is optional Codable data; no SwiftData model property was added. Existing version 4 migration machinery remains in place; populated legacy/unversioned and versioned fixture tests cover preservation. Failed container loading retains the store and recovery UI. Historical nutrition remains a snapshot. Cross-bundle-ID installations do not share an iOS container; export/import is required to transfer between identities.

USDA and Open Food Facts remain the database choices; FatSecret was not substituted silently. The UI identifies Open Food Facts as the researched free alternative, with explicit packaged-product review and attribution. Barcode lookup prefers the local library, then exact OFF lookup and exact-normalized USDA branded GTIN verification. Source-only meal search caches cannot masquerade as complete barcode lookups. AI planning never supplies the nutrient arithmetic for verified database records.

## Verification record

Final unit result: **134 passed, 0 failed, 0 skipped, 0 expected failures** (132 Swift Testing declarations plus 2 XCTest rendering methods). Result bundle: `/private/tmp/fueli-rigorous/Logs/Test/Test-Fueli-2026.11.01_21-59-08--0500.xcresult`. All four required AI/USDA live tests and both optional USDA/OFF integrations were enabled and executed. The new log-only backup regression also verifies preserved source ID, canonical barcode and full-precision standard/selected quantities without saving a library food. The annotated receipt fixture verifies 25 rows, the long receipt reconstructs 131 rows, and multi-page duplicate/overlap purchases remain unconfirmed.

Command:
```sh
TEST_RUNNER_FUELI_RELEASE_LIVE=1 TEST_RUNNER_FUELI_LIVE_USDA_TESTS=1 TEST_RUNNER_FUELI_LIVE_OFF_TESTS=1 TEST_RUNNER_FUELI_LIVE_SECRETS_PATH="$PWD/.fueli-test-secrets.json" xcodebuild -project Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=F4495C04-B58D-492A-8B39-8E9A294AE08C' -derivedDataPath /private/tmp/fueli-rigorous -parallel-testing-enabled NO -jobs 2 -only-testing:FueliTests test
python3 -m unittest discover -s scripts -p 'test_*.py' -v
bash -n release.sh scripts/test_all.sh
```

Release-script regression tests: **4 passed**, including adversarial rejection of failed/skipped/empty/incomplete runs, stale source/commits, dirty source, incorrect IPA hashes, missing physical confirmation, excluded tests, wrong bundle/version and bundled credentials. Shell syntax and `git diff --check` passed.

Final UI result: **18 passed, 0 failed, 0 skipped, 0 expected failures**. Result bundle: `/private/tmp/fueli-rigorous-ui/Logs/Test/Test-Fueli-2026.11.01_21-59-03--0500.xcresult`.

```sh
xcodebuild -project Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=F07FDBCB-D538-4C18-8C2F-B2EE71855A0B' -derivedDataPath /private/tmp/fueli-rigorous-ui -parallel-testing-enabled NO -jobs 2 -only-testing:FueliUITests test
```

The numeric saved-food edit/history workflow also passed three consecutive iterations on the compact simulator. The final full run includes that workflow again. Successful screenshot attachments were exported and visually reviewed for the product match/quantity, receipt OCR review and fractional saved-food confirmation; onboarding, goals/settings and backup screenshots are also retained in ignored `ReviewArtifacts/rigorous-1.0.14/`.

Measured app line coverage, independently per run: unit/rendering/live suite **23.63% (3,683/15,587 lines)**; UI suite **73.11% (11,396/15,587 lines)**. These percentages must not be added. Coverage is not proof that every branch, provider, device or input works. No universal correctness or clinical accuracy claim is made. Earlier full runs exposed failures and a test-host restart; they are retained locally and do not satisfy the publication gate.

The signed archive at `/private/tmp/Fueli-1.0.14-verified.xcarchive` succeeded. Verified version 1.0.14, bundle `com.welford.fueli`, team `8RBLV22YJJ`, valid code signature, HealthKit enabled in both app entitlements and provisioning profile, no bundled USDA key, and no Debug mock endpoint/test-store arguments/test photograph. `Fueli.ipa` is packaged from that exact archive, not the latest arbitrary archive on the machine.

Additional builds passed: Free for generic iPhone (unsigned build check; HealthKit disabled), and Release reconstructed from publishable files with only the blank example configuration. No private configuration was required to compile the public source. The supplied custom Gemma gateway was the only provider exercised live; other provider transport contracts were tested with mocks.

The user confirmed camera scanning and Apple Health work on their physical device. This is user-reported acceptance; the agent did not instrument a connected iPhone. Vendor synchronization, motion-sensor accuracy, all possible receipts, all OS versions and clinical outcomes are outside what these fixtures establish. Only iOS 26.5 was installed for simulator execution; minimum deployment remains iOS 18.

## Reproduce and configure

See [TESTING_RELEASE_PLAN.md](TESTING_RELEASE_PLAN.md) for Context7/Apple references, primary comparable-app test sources, full commands, the private JSON template, release evidence schema and manual acceptance reference. No new API key was needed: the supplied AI configuration and existing USDA key succeeded in live checks. Open Food Facts needs no API key. Release intentionally excludes personal credentials; users configure their own keys in Settings.

## Affected files

```text
.gitignore
Fueli.xcodeproj/project.pbxproj
Fueli.xcodeproj/xcshareddata/xcschemes/Fueli.xcscheme
Fueli/App/FueliApp.swift
Fueli/App/RootView.swift
Fueli/App/UITestBootstrap.swift
Fueli/DATABASE_LOOKUP_RESEARCH.md
Fueli/MEAL_LOOKUP_FIX.md
Fueli/Models/UserProfile.swift
Fueli/OVERHAUL_STATUS.md
Fueli/RIGOROUS_TEST_REPORT.md
Fueli/Resources/Info.plist
Fueli/Secrets.example.xcconfig
Fueli/Services/AINutritionService.swift
Fueli/Services/AIProviderConfig.swift
Fueli/Services/BarcodeLookupService.swift
Fueli/Services/KeychainStore.swift
Fueli/Services/LibraryTransfer.swift
Fueli/Services/MealFoodDatabase.swift
Fueli/Services/NutritionAnalysisResult.swift
Fueli/Services/NutritionCommitter.swift
Fueli/Services/OpenFoodFactsSearchService.swift
Fueli/Services/PedometerService.swift
Fueli/Services/RetailBarcode.swift
Fueli/TESTING_RELEASE_PLAN.md
Fueli/Views/Dashboard/DashboardView.swift
Fueli/Views/History/HistoryView.swift
Fueli/Views/Logging/DescribeMealFlowView.swift
Fueli/Views/Logging/EditMealView.swift
Fueli/Views/Logging/LogEntryHubView.swift
Fueli/Views/Logging/ManualEntryView.swift
Fueli/Views/Logging/MealAnalysisFlow.swift
Fueli/Views/Logging/MealBuilderView.swift
Fueli/Views/Logging/NutritionConfirmView.swift
Fueli/Views/Logging/PhotoCaptureFlowView.swift
Fueli/Views/Logging/ReceiptImportView.swift
Fueli/Views/Logging/SavedMealsFlowView.swift
Fueli/Views/Onboarding/OnboardingFlowView.swift
Fueli/Views/Settings/ProfileSettingsView.swift
Fueli/Views/Settings/SettingsView.swift
FueliTests/AIWireContractTests.swift
FueliTests/ApplicationFixtures/IMAGE_PROVENANCE.md
FueliTests/ApplicationFixtures/banana.jpg
FueliTests/FueliTests.swift
FueliTests/MealDatabaseChoiceTests.swift
FueliTests/MealLookupTests.swift
FueliTests/MealReviewRenderingTests.swift
FueliTests/OFFFixtures/OFF_PROVENANCE.md
FueliTests/OFFFixtures/cream-cheese-product.json
FueliTests/OFFFixtures/search.json
FueliTests/OpenFoodFactsSearchTests.swift
FueliTests/OverhaulExpansionTests.swift
FueliTests/PersistenceActionTests.swift
FueliTests/ReceiptFixtures/annotated-rows.json
FueliTests/ReceiptLayoutTests.swift
FueliTests/ReleaseLiveTests.swift
FueliTests/RigorousDomainTests.swift
FueliTests/USDAFixtures/README.md
FueliTests/USDAFixtures/bagel-detail.json
FueliTests/USDAFixtures/bagel.json
FueliTests/USDAFixtures/cream-cheese-detail.json
FueliTests/USDAFixtures/cream-cheese-sr-detail.json
FueliTests/USDAFixtures/cream-cheese.json
FueliUITests/AppJourneyTests.swift
README.md
fueli-test-secrets.example.json
project.yml
release.sh
scripts/test_all.sh
scripts/test_release_gate.py
scripts/verify_release.py
```

Final archive/build commands:

```sh
xcodebuild archive -project Fueli.xcodeproj -scheme Fueli -configuration Release -destination 'generic/platform=iOS' -archivePath /private/tmp/Fueli-1.0.14-verified.xcarchive -derivedDataPath /private/tmp/fueli-release-check -allowProvisioningUpdates -jobs 2 USDA_API_KEY=
xcodebuild -project Fueli.xcodeproj -scheme Fueli -configuration Free -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/fueli-free-check -jobs 2 CODE_SIGNING_ALLOWED=NO USDA_API_KEY= build
```

Packaging copied `Products/Applications/Fueli.app` from the exact verified archive into a temporary `Payload/` and zipped that directory to `Fueli.ipa`. The existing `~/bin/make-ipa.sh` selects the globally newest archive, so it was intentionally not used to select this candidate. Signature, version, bundle, HealthKit app/profile entitlements, all app files for configured-key matches, absence of test fixtures/hooks and the final IPA SHA256 were checked before publication. SHA256: `26e9c34b245647e1568b190d34f401e456bffc3036f1f61dbeb125e7829fc4fc`.
