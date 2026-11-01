# Current implementation and verification

This report supersedes the earlier incremental notes in IMPLEMENTATION.md. The full original acceptance matrix is not yet completely met; remaining gaps are listed below.

## Health data fix

The selected developer team has a Fueli-specific provisioning profile with HealthKit enabled. The existing repository IPA's profile also enables HealthKit. This does not prove which binary/profile is installed on the physical iPhone.

A real code defect rejected valid resting-energy daily aggregate samples unless their raw sample durations covered 90% of the day. That invented completeness gate has been removed. Seven paired completed days of active plus resting energy are still needed for a stable average. The UI now reports how many days contain each type and both, instead of confusing missing paired history with a failed query. HKError.errorNoData is handled as an empty result; genuine errors remain errors. Free builds compile with HEALTHKIT_DISABLED. No Health store is reset.

## Added implementation

- One SwiftData library using the existing stable-UUID SavedMeal records; ingredient snapshots distinguish recipes from individual foods. Canonical barcode and source record ID are stored independently from serving descriptions.
- My Foods supports search, alphabetical/favorite/recent/frequent browsing, updates, confirmed deletion, and quantity confirmation before logging.
- Create Meal combines saved foods deterministically, supports fractional standard servings and known gram/ounce or milliliter/US-fluid-ounce quantities, removes ingredients, saves/edits reusable recipes, or logs a snapshot. Saved recipes can be logged with multipliers.
- Confirmation separates Log Food and Save to My Foods. Known mass and volume references support gram/ounce or milliliter/US-fluid-ounce entry, without density assumptions. Recipe nutrition fields cannot be independently edited apart from ingredients. Logs retain library IDs and recipe snapshots. Photo/text snapshots retain preparation, raw/cooked/as-packaged basis and an estimated-quantity flag, with a visible portion-estimate warning at confirmation.
- On-device receipt capture uses VNDocumentCameraViewController for multiple pages or PhotosPicker for up to 20 images. On iOS 26, RecognizeDocumentsRequest provides structured text lines; iOS 18 uses accurate VNRecognizeTextRequest, also used on structured-recognition failure. Local OCR normalizes image orientation, groups fragments spatially, preserves original text/confidence, and uses deterministic abbreviation/quantity/price parsing. Review permits name/purchase-quantity/unit corrections, skip/non-food marking, existing-food reuse, explicit USDA candidate selection, and no-suitable-match rejection. Imported products use a 100 g USDA standard, never purchased quantity, and never create consumption logs. Repeated FDC imports are deduplicated by source ID. Original page previews are available.
- Photo analysis now has a typed observation/estimate/unknown description stage, editable review, and a separate text-only USDA query-planning call. Corrected labels/order/weights are authoritative. Provider requests include OpenAI-compatible response_format JSON Schema or Anthropic output_config.format JSON Schema. An explicit unsupported-parameter response permits one fallback to prompt-only output. Local decoding/quantity validation is always enforced; planning retries malformed output once. Final totals retain source/weight ingredient snapshots and can be saved as recipes. USDA candidate matching is deterministic and can reject ambiguity or unrelated foods; ambiguous candidates have a user-choice/no-suitable-match screen; raw/cooked and recognized preparation terms constrain matching. Detailed records are fetched by ID and kcal/kJ/gram units validated, including Foundation Atwater energy IDs 2047/2048. Existing saved USDA foods can be refreshed by ID for review.
- Barcode lookup uses OFF API v3 with typed DTOs, an identifying User-Agent, timeout, cache, retry/backoff/jitter for server errors, rate-limit cooldown, exact code verification, and USDA exact-GTIN branded fallback. Missing nutrients/basis require review. Explicit total carbohydrate takes priority; fiber is added to available carbohydrate only when both are known. Both-source material conflicts produce a review warning. Multiple visible barcodes are not automatically chosen; failed requests require explicit retry.
- Versioned JSON nutrition backup exports foods, recipes, logs, metadata, references, and optionally images. Files export uses FileDocument/system file export; imports use security-scoped coordinated reads, file-size/version/content validation, additive UUID/canonical-barcode deduplication, reference remapping, explicit import confirmation, and transactional save. Existing history is never overwritten. Profile/weight/water/workouts are outside this nutrition-backup scope.

## Migration

Frozen schemas cover the original unversioned repository, the intermediate Health-setup schema, and the initial library-preview schema. FueliMigrationPlan moves these to CurrentFueliSchema version 4, including frozen version 2 and version 3 library schemas. Version 4 adds an optional manual total-burn baseline. Optional precise calorie fields preserve existing integer values as a fallback and retain full Double precision for new calculations and snapshots. Legacy favorites are marked as favorites after migration. Tests populate and reopen actual disk stores, checking history, photos, favorites, profiles, water, weight, workouts, and Health baseline retention. An unreadable-store test verifies the original bytes are not removed or replaced. Unknown experimental schemas still show recoverable failure; no delete/recreate fallback exists.

## Executed checks

Newest installed runtime: iOS 26.5. Device: iPhone 17 Pro, 9EDE4995-25DA-4E2F-9C4A-67E57E644D0F.

```
xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-health-repro test
xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -configuration Debug -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-ui-review CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

Test result: 60 passed tests (61 passing executions including parameterized migration cases), one optional credential-dependent live AI test skipped, no failures. Result bundle: /private/tmp/fueli-health-repro/Logs/Test/Test-Fueli-2026.10.31_12-53-07--0400.xcresult. Both actual Vision OCR paths ran against SyntheticReceipt.png inside the simulator test suite. No accuracy percentage is asserted from this small fixture set. URLProtocol fixtures verify rate-limit cooldown and malformed product responses. Migration fixtures include a populated version 2 library upgraded to version 3. Precision and backup tests retain fractional calories, macros, quantities, and volume definitions.

Manual simulator checks opened the dashboard, expanded logging hub, receipt entry, system photo picker, and OCR review. A synthetic receipt produced unresolved review rows and no automatic imports. A 150-kcal standard serving selected at 2.5 servings showed 375 kcal and saved only 150 kcal to My Foods without adding a log. Reopening the food and logging 0.5 servings produced 75 kcal. A two-ingredient recipe (2 + 0.5 standard servings) showed 375 kcal and saved independently of the daily log. After installing the latest version 3 build over this populated simulator, the dashboard retained the 75-kcal log, profile and fractional macros. Screenshots in ../ReviewArtifacts document these states. They do not prove every flow works. Files export created Fueli-nutrition-backup.json; importing it back reported Added 0 records, confirming duplicate skipping in the UI. Reopening the retained recipe and selecting 0.5 portions showed 187.5 kcal rounded to 188 for display and 12.5 g protein. Updating a saved 150-kcal food with three servings selected displayed a one-standard-serving save confirmation and left today’s log empty. The model settings showed gemma-4-31b-it as Text + Vision using the exact Hugging Face publisher repository. Typing an unconfirmed model exposed Use Anyway and its warning; canceling, leaving and reopening preserved the saved Gemma configuration. The native Simulator window controller intermittently fails with cgWindowNotFound; direct simctl screenshots remain available. Source and test builds use separate output directories to avoid installing a bundle being rewritten by tests. git diff --check passed.

## Remaining original acceptance gaps

- No full end-to-end UI automation matrix for all nine original workflows. Physical camera recognition, real vendor/Watch sync, and provider vision responses still need device checks. Files export and repeat import were exercised with synthetic records in the simulator. With explicit user approval on 2026-10-31, both simulator read permissions were granted and the empty-history flow was exercised. Physical iPhone data remains unverified.
- Configurable provider JSON Schema requests and explicit unsupported-parameter fallback are implemented and contract-tested; live compatibility with every gateway/model has not been tested.
- Receipt parsing has spatial grouping and deterministic fixtures, but not a validated multi-merchant/low-quality corpus, robust page-overlap reconciliation, or crop highlighting. Receipt import history is not persisted (optional in the original specification). Do not infer broad OCR accuracy from one synthetic image.
- API product-image downloading, exhaustive USDA household-portion metadata, and detailed nutrition completeness/status UI remain incomplete. Unknown optional fiber is rejected for review rather than stored/displayed as an explicit unknown nutrient. Unsupported serving conversions remain unavailable rather than guessed.
- The deployment target is now iOS 18; the SDK availability build passed, but no iOS 18 runtime is installed for execution tests. No physical iPhone build or replacement IPA was installed in this task.

## Physical iPhone acceptance checklist

1. Install a HealthKit-enabled build; grant both Active and Resting Energy, inspect paired-day counts, and compare the average to Health. Also deny one type and verify the fallback explanation.
2. Scan a barcode, select 2.5 servings, and log; repeat with Save to My Foods and verify only one standard serving is stored. Test an invalid code and explicit retry.
3. Reopen My Foods offline, log half a serving, edit the saved food, and verify old logs do not change.
4. Build a meal with two foods, edit quantities/remove an ingredient, save, reopen, and log a multiplier.
5. Photograph a meal, inspect observed/estimated/unknown details, correct grams/preparation, then continue lookup and inspect source snapshots.
6. Scan/choose a multi-page receipt, correct rows, reject unsuitable matches, import only reviewed foods, and verify no daily logs were added.
7. Export with and without images; import into a separate fresh test installation and repeat import, verifying duplicates are skipped and prior history retained.

## Documentation checked during follow-up

Checked 2026-10-30 using Context7 and primary documentation: Apple Vision/RecognizeDocumentsRequest (iOS 26 availability confirmed in the installed SDK), SwiftData VersionedSchema/SchemaMigrationPlan, HealthKit statistics/source queries, USDA v1 search/detail and Foundation Foods energy documentation, Open Food Facts v3 product reads, OpenAI Chat Completions structured outputs and Anthropic Messages structured outputs. USDA's Foundation documentation defines 2047 as general Atwater energy and 2048 as food-specific Atwater energy; Fueli prefers legacy 1008 when supplied, otherwise 2048, then 2047, then kJ 1062 converted to kcal. These values are alternatives, never additive.

Sources: https://fdc.nal.usda.gov/Foundation_Foods_Documentation/ ; https://developer.apple.com/documentation/vision/recognizedocumentsrequest ; https://developers.openai.com/api/docs/guides/structured-outputs ; https://platform.claude.com/docs/en/build-with-claude/structured-outputs . Strict schema output constrains shape; it does not verify a model's food observations or quantities.

## Affected files

Persistence: App/FueliApp.swift, Models/FoodLog.swift, Models/SavedMeal.swift, Models/UserProfile.swift; new Models/FueliSchema.swift.

Domain/services: Services/AINutritionService.swift, BarcodeLookupService.swift, HealthKitService.swift, NutritionAnalysisResult.swift; new ServingNutrition.swift, RetailBarcode.swift and LibraryTransfer.swift. Existing fdc_ingredient_prompt.md remains the query-plan contract.

UI: logging hub, barcode/photo analysis coordination, nutrition confirmation, manual/edit entry, My Foods, dashboard/history, onboarding, provider/profile/settings; new MealBuilderView.swift and ReceiptImportView.swift.

Tests: FueliTests.swift optional live-test gate; new HealthActivityTests, HealthConnectionTests, HealthEnergyPlanTests, ModelCapabilityTests, NutritionSafetyTests, MigrationSafetyTests, OverhaulExpansionTests and SyntheticReceipt.png. NutritionRegression contains the earlier standalone assertion harness.

Build/documentation: Fueli.xcodeproj/project.pbxproj, project.yml, README.md, Secrets.example.xcconfig, CALORIE_EVIDENCE.md, HEALTH_CONNECTIONS.md, MODEL_CAPABILITIES.md, IMPLEMENTATION.md and this report. ReviewArtifacts contains synthetic simulator screenshots. Unrelated untracked .agents content was preserved.

## Project regeneration check

The XcodeGen spec now includes the unit-test target/scheme, OCR fixture, prompt resource, iOS 18 deployment target, ignored local xcconfig and explicit Free configuration. Context7 verified that resource files belong under sources with buildPhase: resources; an unsupported target-level resources key would be ignored.

To preserve the loaded signing team and existing project state, generation was verified in a temporary copy containing no real API keys:

```
xcodegen generate --spec /private/tmp/fueli-project-spec-check/project.yml --project-root /private/tmp/fueli-project-spec-check --project /private/tmp/fueli-project-spec-check
xcodebuild -project /private/tmp/fueli-project-spec-check/Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-generated-project-check CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build-for-testing
```

Result: generation succeeded; TEST BUILD SUCCEEDED. This compiles the regenerated application and test bundle; it is not an additional test execution. The checked-in project retains the existing signing settings. The personal Secrets.xcconfig is ignored; Secrets.example.xcconfig contains no key.

Final source review: git diff --check passed. A targeted scan of changed/new Swift source found no provider-key-shaped tokens, private-key blocks or hardcoded key assignments. This is a limited scan, not a security audit. The personal USDA configuration and Keychain credentials were not copied into review artifacts or the temporary project-generation fixture.

## Approved Health permission check — 2026-10-31

The user explicitly approved read-only Active and Resting Energy permissions in the simulator. Both system permission prompts were enabled and allowed. No Health write access was requested or granted in this check.

The dashboard query completed and reported no readable Active Energy for today. Health Connections found no recent readable energy sources. Update Baseline from Shared Data completed without a query error and showed 0 active-energy days, 0 resting-energy days and 0 paired days in the preceding 14 completed days. The app explicitly retained the existing calorie plan. This verifies the permission/empty-history workflow; it does not reproduce or establish the state of the user's physical iPhone Health store. Screenshot: ../ReviewArtifacts/17-health-permissions-empty-history.png. No code changed for this permission check; the previously recorded automated test/build results remain applicable.

## Manual total daily burn — 2026-10-31

Setup and Goals & Profile now share ManualBurnInput: a validated full-day total burn, a live goal adjustment/intake preview, and an explicit Use This Daily Burn action. It includes resting energy and all activity; nothing is added twice. Manual baseline > saved Health average > body/activity estimate. An explicit manual food-intake override remains higher priority, with a visible explanation. A successful Health import switches from manual to Health; failed/sparse imports retain the manual value. Setup skips activity questions once either baseline is selected. The dashboard explains which source determines the budget.

The clinical/sport evidence was rechecked using primary sources. Existing cut/bulk dose limits remain. Recomp fat loss now caps its 10% adjustment at 500 kcal/day, informed by the Murphy/Koehler resistance-training meta-analysis; this is an app guardrail, not a universal biological threshold. Added in-app research explanations/links for maintenance, cutting, muscle gain and recomp. Exact percentages are labeled starting policies rather than clinically validated personalized doses; CALORIE_EVIDENCE.md records populations and limitations.

Frozen PrecisionFueliSchema preserves version 3, and a lightweight migration adds manualMaintenanceCalories in version 4. Tests populate and migrate version 3 food/history/profile/weight/water/workout records without resetting them. Added manual-baseline priority, all-goal calculations, invalid/nonfinite entry and persistence tests. Final follow-up run: 65 passed tests (66 passing executions), 1 optional live AI test skipped, 0 failures. Result: /private/tmp/fueli-health-repro/Logs/Test/Test-Fueli-2026.10.31_13-25-51--0400.xcresult.

Commands:
```
xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-health-repro test
xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -configuration Debug -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-ui-review CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build
```

Build passed. Manual settings check: 2500 total burn → maintenance-focused recomp intake 2500; fat-loss recomp → adjustment -250, intake 2250. Saving and reopening retained the value. Existing simulator preferences were restored after testing. Screenshot: ../ReviewArtifacts/18-manual-burn-settings-targets.png. A separate simulator-only bundle ID com.welford.fueli.manualburnreview is used for fresh-onboarding checks, avoiding any reset of the existing app's data. Its build used the same project/source with PRODUCT_BUNDLE_IDENTIFIER overridden, in /private/tmp/fueli-manual-burn-onboarding.

Fresh setup was tested in the isolated review app with synthetic measurements and a cut goal. Entering 2500 kcal/day previewed -550 kcal/day and 1950 kcal/day intake. Applying it skipped both steps/workout questions and advanced directly to diet preference. The summary retained the manual-burn source and 1950-kcal target. Screenshots: 19-manual-burn-setup.png and 20-manual-burn-setup-summary.png. Numeric entry has an explicit Done control; applying a burn dismisses its keyboard, and the weight-entry Done action is scoped to the weight field.

The isolated setup-review app was removed after verification. The original Fueli simulator app/store was preserved and the final version 4 build was reinstalled. The main simulator profile was returned to its original maintenance-focused recomp/activity-estimate settings after the temporary manual-burn checks.

## Release 1.0.12 preparation

Fresh signed Release archive succeeded at /Users/matteowelford/Library/Developer/Xcode/Archives/2026-10-31/Fueli-1.0.12.xcarchive. App version 1.0.12, iOS minimum 18.0, signing team 8RBLV22YJJ; signature verification passed and both app/profile enable HealthKit. The public archive/IPA contains an empty bundled USDA_API_KEY. Personal USDA keys can now be entered in Settings → Food Database and stored in device-only Keychain, with checked update/delete results; request-time resolution avoids restart. Debug's optional local bundle configuration remains a fallback. Release/Free configurations explicitly exclude it. The actual Keychain fixture uses a unique disposable account and does not alter personal credentials.

Final release suite: 67 tests passed (68 passing executions), one optional live AI test skipped, zero failures. Result: /private/tmp/fueli-health-repro/Logs/Test/Test-Fueli-2026.10.31_15-32-31--0400.xcresult. Archive command: xcodebuild archive -project ../Fueli.xcodeproj -scheme Fueli -configuration Release -destination 'generic/platform=iOS' -archivePath /Users/matteowelford/Library/Developer/Xcode/Archives/2026-10-31/Fueli-1.0.12.xcarchive -allowProvisioningUpdates USDA_API_KEY=

Packaging used /Users/matteowelford/bin/make-ipa.sh from the repository root. Packaged version, empty bundled key and executable hash were checked against the fresh archive. Local ReviewArtifacts screenshots are review-only and excluded from the public commit; no personal API key or simulator store is published.
