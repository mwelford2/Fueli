# Ingredient review and USDA lookup follow-up — 2026-11-01

## Findings and behavior

The populated numeric input used its title only as a placeholder. Ingredient review now keeps **Estimated weight (g)** visible, with an ingredient-specific VoiceOver label. Describe Meal and Photo scroll so longer reviews and match choices remain reachable.

Public USDA requests reproduced several distinct conditions for “everything bagel with cream cheese”:

- Generic search returns `Bagel` and `Bagels, …`, without necessarily identifying the everything topping. Exact-token matching rejected singular/plural equivalents and correctly refused to invent a topping match. Bagel/bagels now normalize identically. A deliberately narrow everything-bagel fallback offers the unqualified generic bagel for explicit review, never silently substitutes it or selects seasoning, chips, or an arbitrary branded product.
- The cream-cheese search returned Foundation food **2346385**, below the old five-result limit. Its detail record omits fiber. SR Legacy **173418** includes all required values and explicit zero fiber. The old resolver stopped at the preferred incomplete record. The resolver now checks details and can try the next defensible identity, with a maximum of three incomplete detail records per ingredient. Missing nutrients are still not converted to zero. A user-selected record is respected and must itself pass nutrition validation.
- A GET search returned HTTP 400 during investigation, while documented POST searches succeeded. This observation does not establish the cause of that particular HTTP 400. Searches now use typed POST JSON with an array of USDA data types and 50 candidates. Transient connection/408/5xx retries remain bounded; rate limits, rejected requests, invalid JSON and completed searches with no suitable match remain distinct.

An explicit match choice now reaches detailed nutrition even when it intentionally relaxes the original description. Retrying USDA or choosing a candidate reuses the already validated AI query plan. Editing ingredients clears the plan and choices. The query planner cannot mark a user-retained ingredient negligible. Failed lookup offers **Edit ingredients** and identifies the unresolved ingredient where applicable.

Nutrition arithmetic and historical persistence schemas are unchanged. No migration or configuration change is needed. Published builds still require the user's USDA key in Settings → Food Database.

## Verification

Environment: Xcode 26.6.0, iPhone 17 Pro simulator, iOS 26.5. The deployment target remains iOS 18.

Initial regression reproduced the singular/plural failure. An end-to-end fixture calculation then exposed the missing Foundation fiber record; the corrected resolver selects the complete SR Legacy record. The calculation test preserves corrected 110.5 g bagel and 28.25 g cream-cheese quantities, source IDs and full-precision totals. It requires explicit review for the generic bagel approximation.

Full suite:

```sh
xcodebuild -project Fueli.xcodeproj -scheme Fueli \
  -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' \
  -derivedDataPath /private/tmp/fueli-meal-fix test
```

Result: **80 passed test cases, 2 optional live cases skipped, 0 failures** (83 passing executions including parameterized cases). The app and test targets compiled. Log: `/private/tmp/fueli-meal-full.log`; result: `/private/tmp/fueli-meal-fix/Logs/Test/Test-Fueli-2026.11.01_15-19-18--0500.xcresult`.

Coverage added: real response decoding; singular/plural identity; explicit approximation; incomplete-detail fallback with explicit zero versus missing fiber; corrected fractional weights and combined nutrition; primary/fallback requests; unrelated-product rejection; preparation mismatch; HTTP 400/403/429; malformed JSON; offline errors; missing-key configuration; and coordinator retry/choice/edit behavior. A rendered SwiftUI review is attached to the test results.

Final targeted check, including the optional live test:

```sh
TEST_RUNNER_FUELI_LIVE_USDA_TESTS=1 xcodebuild \
  -project Fueli.xcodeproj -scheme Fueli \
  -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' \
  -derivedDataPath /private/tmp/fueli-meal-fix \
  -only-testing:FueliTests/MealLookupTests \
  -only-testing:FueliTests/MealReviewRenderingTests test
```

Result: **13 passed, 1 failed** (15 passing executions). The optional live test failed because USDA returned **HTTP 429** on a food-detail request using its shared public DEMO_KEY. It was not treated as a missing food. No further live retries were made. Therefore a completed live simulator resolution is **not verified**. Earlier live public requests successfully supplied the committed search/detail fixtures. The AI provider and the user's physical-phone failure were not reproduced live.

The corrected final render was exported and visually inspected: both populated inputs retain their gram labels, and Continue to USDA Lookup is visible. Local image: `ReviewArtifacts/21-ingredient-weight-labels.png` (ignored). Result: `/private/tmp/fueli-meal-fix/Logs/Test/Test-Fueli-2026.11.01_15-21-04--0500.xcresult`. `git diff --check` passed.

## Files and documentation

- Services: `AINutritionService.swift`, `NutritionAnalysisResult.swift`.
- Shared review/coordinator: `MealAnalysisFlow.swift`; scrolling containers: `DescribeMealFlowView.swift`, `PhotoCaptureFlowView.swift`.
- Tests: `MealLookupTests.swift`, `MealReviewRenderingTests.swift`, `USDAFixtures/*.json` and its provenance README. New tests/resources are included through the existing synchronized test group; no app source files were added.
- README and this report.

Context7 consulted Apple's SwiftUI reference for persistent visible/accessibility labels. Its USDA search returned a third-party client reference; API behavior was checked against the primary [USDA API guide](https://fdc.nal.usda.gov/api-guide/) and v1/OpenAPI 1.0.1, then actual public responses. USDA permits POST search with an array of data types and documents the lower DEMO_KEY rate limit. Fixture provenance and data reduction are recorded in `FueliTests/USDAFixtures/README.md`.

Manual acceptance: describe the meal, inspect both gram labels, correct a weight, continue lookup, review/accept a generic bagel approximation only if appropriate, inspect the final ingredient sources/totals, then independently log or save. Rejecting every candidate must return to editable ingredients. With connectivity disabled, Retry should reuse the plan and preserve edits. Exact topping nutrition still requires a suitable record or separately identified ingredients; a photograph/text estimate does not establish a measured portion.
