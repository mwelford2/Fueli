# Comprehensive verification and release gate

The next release is conditional on passing required checks; skipped/blocked tests are not passes. Tests cannot establish correctness for every possible input or prove clinical accuracy. The required app identifier is `com.welford.fueli`.

## Plan and affected areas

1. Audit all models, services and user journeys. Derive additional cases from primary open-source nutrition-app tests and Apple's testing docs. Preserve the database changes and existing stores.
2. Add deterministic API injection and adversarial/property tests for nutrition, servings, barcode branches, provider contracts, cancellation, missing data, receipts, backup transactions, persistence, goals, activity, water/weight and date boundaries. Fix demonstrated defects.
3. Add XCTest UI journeys using isolated synthetic stores: onboarding, hub/navigation, manual save/log, fractional saved-food use, recipes, edits/deletes, history, water, workouts, goals/settings, source choices, backup entry points and error/cancel paths. Exercise compact/current simulators and retain screenshots. Never reset the real store.
4. Run configured AI text/vision/planning and USDA/OFF integrations separately without exposing keys. Required release tests fail when credentials are unavailable. USDA and the legacy Gemma text connection were checked before testing changes.
5. Inspect coverage and enumerate device-only checks. A real camera, physical motion and populated Health/vendor synchronization cannot be proven by mocked simulator tests. Required unverified checks block release rather than silently count as passes.
6. Only after required gates pass: patch-bump, fresh Release archive, verify bundle ID/signing/HealthKit/absence of secrets and test hooks, package IPA, verify hash/source, publish and update feed. User's release authorization is conditional on the results.

Affects tests/fixtures, project/scheme, Debug-only isolated UI test bootstrap, AI networking injection, domain/persistence validation where failures demonstrate defects, accessibility identifiers, README/report and release scripts. No backend, destructive recovery, unrelated rewrite or personal test data.

## Comparable-app sources

- OpenNutriTracker: https://github.com/simonoppowa/OpenNutriTracker/blob/main/test/features/meal_detail/meal_detail_add_double_tap_test.dart — pending/repeated save creates one log.
- https://github.com/simonoppowa/OpenNutriTracker/blob/main/test/features/meal_detail/meal_detail_missing_value_test.dart — missing nutrients differ from true zero.
- https://github.com/simonoppowa/OpenNutriTracker/blob/main/test/features/add_meal/data/repository/products_repository_portion_label_test.dart — portion metadata remains tied to the verified food.
- wger: https://github.com/wger-project/wger/blob/master/wger/nutrition/tests/test_nutritional_calculations.py — summed nutrients and unit/per-body-mass conversion.
- https://github.com/wger-project/wger/blob/master/wger/nutrition/tests/test_log_item_api.py — date scoping and record isolation. Fueli adapts these to local stores/history rather than server accounts.
- Apple XCTest via Context7 `/websites/developer_apple_xctest`: XCUIApplication interactions, explicit assertions/waits, retained screenshot attachments. Rendering a view alone is not a UI workflow assertion.

Checked 2026-11-01. Public source files were read; test ideas are independently adapted to Swift. No third-party test implementation or accuracy statistic is copied.

## Reproduction and evidence

Keep `.fueli-test-secrets.json` private (ignored; example: `fueli-test-secrets.example.json`). `apiKey` configures the saved AI endpoint/model; optional `usdaKey` overrides the local Debug USDA key for live tests. Never put credentials in command arguments or tracked fixtures.

```sh
FUELI_TEST_DESTINATION='platform=iOS Simulator,id=<installed-simulator-UUID>' bash scripts/test_all.sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
bash -n release.sh scripts/test_all.sh
```

The script enables **all** opt-in live checks. Ordinary local test runs may skip live tests; they are insufficient release evidence. Swift Testing parameter cases exercise hundreds of combinations; declared-test counts and parameter executions must not be conflated.

`release.sh` now publishes the **exact previously tested `Fueli.ipa`**, without repackaging the latest arbitrary archive. It requires ignored `.fueli-release-evidence.json`. `scripts/verify_release.py` verifies the source commit/clean tree, recorded source fingerprint, IPA hash, source/plist version, `com.welford.fueli`, no bundled USDA key, nonempty passing xcresults, zero failures/skips/expected failures, all declared unit/UI/live tests, and device confirmation. See the script docstring for fields. Record `sourceFingerprint` before starting candidate tests; populate source commit/IPA hash only for the actual reviewed candidate. Do not fabricate result bundles or physical checks.

The user confirmed camera scanning and Apple Health functionality on their device on 2026-11-01. This is **user-reported acceptance**, not an instrumented device run by this agent. Keep that distinction in the release report. Motion-sensor performance, every vendor synchronization scenario, every possible receipt layout and clinical accuracy cannot be proved by simulator fixtures.

For receipt rows, accurate Vision text OCR is the default: the structured document request showed excessive first-use latency on the compact iOS 26.5 simulator. The iOS 26 structured implementation remains available through `preferStructured: true` and is still exercised alongside the iOS 18-compatible fallback in the standard automated suite. Neither path uploads receipt images.

## Physical acceptance reference

- Camera: scan valid UPC-A/UPC-E/EAN foods; reject invalid codes; verify label/source and a fractional serving before logging.
- Health: allow both Active and Resting Energy; verify completed-day average and no double addition of workouts. Insufficient data retains the existing plan.
- Offline: open a saved food, log 0.5 servings, reopen history.
- Backup: export a private JSON (optionally photos), import into a separate store, verify fractional quantities, recipes and identifiers; repeat import must not overwrite history.
- Upgrade: preserve history/favorites/profile/weight/water/workouts and photos. Cross-bundle-ID installs use separate iOS containers; transfer by backup rather than assuming iOS will merge app identities.
