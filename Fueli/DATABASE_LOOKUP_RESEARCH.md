# Database choices: research and implementation

Checked 2026-11-01. User decisions: database-backed nutrition only; direct requests from the iPhone without an app backend; the same choices after text/photo review; a free alternative is authorized if FatSecret does not fit.

## FatSecret findings

FatSecret **does have a free API**, not just a trial. Its [editions page](https://platform.fatsecret.com/api-editions) lists Basic as self-sign-up, US-only, 5,000 calls/day and requiring attribution. Premier Free requires verification; do not assume approval. Image recognition and natural-language processing are optional usage-billed add-ons, not the free ingredient parser for this implementation.

The [OAuth 2 guide](https://platform.fatsecret.com/docs/guides/authentication/oauth2) specifies the client-credentials flow, a client secret and proxy-based token requests with restricted originating IPs. No public-client/PKCE route was found in these docs. [OAuth 1](https://platform.fatsecret.com/docs/guides/authentication/oauth1) is also supported and signs requests with HMAC-SHA1 and a consumer secret; therefore OAuth 2's proxy requirement alone is not proof that every direct-device API call is impossible. Storing a user's own OAuth 1 credentials in Keychain could avoid shipping a shared secret, but it does not solve the persistence constraint below.

The [storable-data guide](https://platform.fatsecret.com/docs/guides/storable-data) permits indefinite retention of enumerated IDs/tokens and generally limits other cached data to 24 hours. [Food search](https://platform.fatsecret.com/docs/v1/foods.search) lists only `food_id` as storable, and [food details](https://platform.fatsecret.com/docs/v5/food.get) list food/serving IDs. These documented terms do not supply permission for Fueli's indefinitely saved nutrient records, offline recipes, immutable historical snapshots and JSON backups. Those features must not be replaced with remotely refreshed IDs that change history. A different agreement/permission and potentially an authentication backend would need reconsideration before adding FatSecret. No account, paid feature or backend was created.

If such permission were obtained, the supported free search contract is food-name `search_expression`, zero-based `page_number`, up to 50 `max_results`, and `format=json`. Search summary strings such as “Per 1 serving” must not be used as a numeric nutrition reference. Retrieve food details and use an explicit serving ID, its metric amount/unit and nutrients; JSON can return a single object instead of an array for a singleton. Newer Premier search, localization, barcode and NLP features must not be assumed part of Basic.

The useful input strategy is to search **each reviewed ingredient**, retaining brand, food identity, fat/sugar qualifiers and preparation; keep quantities separately for arithmetic. Sending an entire meal narrative to food-name search is not equivalent to ingredient matching. This strategy is implemented deterministically for the selected alternative below.

## Free alternative and tradeoff

**Open Food Facts** is integrated alongside USDA. Its [official API guide](https://openfoodfacts.github.io/openfoodfacts-server/api/) documents keyless reads, open reuse, ODbL database terms, the Database Contents License for individual contents, and CC BY-SA for images. These permit local reusable data under their respective obligations. Fueli displays attribution and retains source identifiers; redistribution of derived databases still needs to honor those licenses. This change does not download product images.

This is a practical complementary packaged-product source, **not a claim of equal FatSecret coverage, curation or nutrition accuracy**. Open Food Facts is community-supplied and explicitly disclaims completeness/accuracy. USDA remains available for generic and prepared ingredients. [Edamam](https://developer.edamam.com/food-database-api) was also checked; its documented persistent caching is limited to eligible paid plans and specified fields, so it does not solve this free local-library requirement. No equally comprehensive and equally curated free replacement was established by this research.

Open Food Facts v3.6 is the current Product Opener API family, but it has no full-text search route. The [Search-a-licious OpenAPI 0.1.0 reference](https://openfoodfacts.github.io/search-a-licious/users/ref-openapi/) documents `POST /search` with `q`, `page`, `page_size`, `langs`, `boost_phrase` and a restricted `fields` list. The production endpoint `https://search.openfoodfacts.org/search` was verified live. Product details use the existing `https://world.openfoodfacts.org/api/v3/product/{code}` reader. A made-up v3 search route or v2 `search_terms` is not used; no legacy CGI search dependency was added.

Context7 was used to resolve FatSecret and Open Food Facts and query authentication, storable data and search/rate-limit documentation. Official publisher docs and real public API responses were checked as above. No third-party wrapper or heavy dependency was introduced.

## Flow and deterministic input handling

1. Text entry lets the user choose a database before AI ingredient review. Alternatively, **Enter ingredients without AI** splits only new lines, semicolons and explicit “with”. “Mac and cheese” is preserved. The split remains editable and is never an automatic food identification.
2. Photos use the configured vision provider to create the existing structured description. Both entry methods stop at the same review: meal description, observed/estimated/unknown information, ingredient names, brands, preparation, nutrition basis and clearly labeled gram weights. The user edits fields or chooses a database and continues. There is no direct AI nutrient-estimate option.
3. Open Food Facts queries are generated in Swift from one corrected component at a time. Remove explicit amounts/units and punctuation/query-language syntax, normalize case/width/diacritics, retain food identity and qualifiers (including percent-fat, skinless/boneless and preparation), and include a supplied brand. Original values remain in the review. The search text is not used to infer grams. Queries over 200 characters require correction.
4. Search uses plain text with phrase boosting, English and 20 records/page. It runs only on Continue/Search/page actions, not on every keystroke. The user chooses a result, then reviews the retrieved package nutrition and calculated amount before **Use this product for this ingredient**. Unrelated or incomplete results need correction/rejection; no result is automatically accepted.
5. Ingredient quantities are authoritative. Package records need a known gram reference and an as-packaged weight. Cooked/raw conversions and volume-to-mass density are not guessed. A 100 mL-only record cannot be applied to estimated grams. Use another record, correct the quantity/basis, or choose USDA/manual nutrition.
6. After all ingredients are confirmed, full-precision deterministic calculations feed the existing nutrition confirmation, separate Log Food / Save to My Foods actions, recipe snapshots and backup. Reference nutrients remain per standard reference, while ingredient servings store the reviewed gram multiplier. Changing database or editing ingredients clears product choices but preserves edited fields. Known brand corrections are also retained by the USDA planner and checked against USDA brand metadata.

AI is used only for the configured image/text description and the existing USDA query-planning route. The Open Food Facts route never sends the image, never requests AI nutrition and never invokes another AI planner. Manual structured entry builds USDA requests deterministically too. Database selection is explicit: the Open Food Facts-only detail reader cannot silently fall back to USDA or reuse a USDA cache entry.

Networking: identifying repository User-Agent, 20-second timeouts, cancellation, a bounded transient retry with backoff/jitter, search spacing of at least 6.1 seconds (10/minute), and product spacing of 4.1 seconds (15/minute). These conservative budgets follow the current [rate-limit guide](https://openfoodfacts.github.io/openfoodfacts-server/api/#rate-limits). Search results are cached 15 minutes, up to 50 query/page entries; product cache reuse is 24 hours. HTTP 429 causes a cooldown using numeric Retry-After or a conservative default. These are app-local budgets; another app/device on the same public IP can still cause a provider rate limit. All failures preserve review state. Late canceled responses are ignored. Replacing the photo clears its old description.

## Persistence and configuration

No SwiftData schema/migration changes. Existing records remain untouched. Recipes keep `OFF:{barcode}` ingredient source IDs and full-precision values in the already supported ingredient snapshots. Backup/restore preserves those fields and does not overwrite existing history.

- Open Food Facts: no account, key or backend needed.
- USDA: existing free personal key in Settings → Food Database.
- Photo/AI text review: existing configured AI provider. No provider is added. AI analysis may incur the configured provider's normal charges; database searches do not add a paid service. Manual text ingredient review can avoid AI calls entirely.
- Existing source/tree work from the prior bagel fix was preserved.

## Verification and limits

New deterministic tests cover unit/quantity cleanup, percent-fat/preparation/brand preservation, conservative splitting, explicit gram/ounce/pound conversions, missing weights, photo review before requests, user corrections, explicit product/label confirmation, database switching, no second AI call for Open Food Facts, manual USDA query construction, canceled stale results, reference scaling, mass/volume/basis rejection, missing nutrients versus explicit zero, source IDs and backup round trip. URLProtocol tests cover request fields, keyless/photo-free POST, real response DTOs, cache/page isolation, duplicates/invalid codes, malformed/error responses, HTTP 429 cooldown, bounded retry and no silent USDA fallback.

Public fixtures in `FueliTests/OFFFixtures` contain a real cream-cheese search and Bega product 9311000999555. Their provenance is in `OFF_PROVENANCE.md`. The product detail's 100 g nutrient reference is kept distinct from its 25 g serving. These examples verify integration and arithmetic, not broad identification accuracy. Other test product values are explicitly synthetic.

Build/test environment: Xcode 26.6.0, iPhone 17 Pro simulator (iOS 26.5), deployment target remains iOS 18. New service files are explicitly in the checked-in app target and automatically covered by project.yml's source directory. Test files/resources use the existing synchronized test group. The two provenance documents have unique bundle names to avoid a resource-copy collision.

Full suite with live Open Food Facts integration enabled:

```sh
TEST_RUNNER_FUELI_LIVE_OFF_TESTS=1 xcodebuild \
  -project Fueli.xcodeproj -scheme Fueli \
  -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' \
  -derivedDataPath /private/tmp/fueli-database-choice test
```

Result: **100 passed cases, 2 skipped, 0 failures** (103 passing executions with parameterized cases). The live test really executed, using the Swift client to search and retrieve the explicitly identified public product. Optional live AI/USDA cases were skipped. Result: `/private/tmp/fueli-database-choice/Logs/Test/Test-Fueli-2026.11.01_15-43-50--0500.xcresult`; log `/private/tmp/fueli-database-full2.log`.

Rendered SwiftUI captures were exported and visually inspected for the editable AI description/database choice, explicit product search results and label/quantity confirmation. They use synthetic data and a test-hosted view, not a physical camera or a live AI-provider response. Live provider-specific vision behavior and physical-iPhone camera interaction remain device acceptance checks. Only iOS 26.5 is installed for simulator execution; iOS 18 runtime behavior was not executed.

Final source verification (including raw/cooked manual queries, negative/ambiguous quantity guards, photo replacement, manual-error recovery, and cache isolation) used the same command **without** `TEST_RUNNER_FUELI_LIVE_OFF_TESTS=1`. Result: **100 passed cases, 3 optional live cases skipped, 0 failures** (103 passing parameterized executions). The app and test targets built successfully. Result: `/private/tmp/fueli-database-choice/Logs/Test/Test-Fueli-2026.11.01_15-57-09--0500.xcresult`; log `/private/tmp/fueli-database-acceptance.log`.

The source-only product cache is separate from the barcode flow's cross-database/conflict-checked cache. A dedicated regression ensures a product chosen during meal lookup cannot cause a later barcode scan to bypass USDA conflict checking. Explicit negative/zero mass quantities are rejected; ambiguous comma-formatted text amounts stay unresolved. Invalid manual entry offers Edit ingredient text rather than a network retry.

`git diff --check` and `plutil -lint Fueli.xcodeproj/project.pbxproj` passed. Existing HealthKit workout deprecation and unused-photo-binding compiler warnings are not introduced by this change. No credentials were added. There are no SwiftData model changes or automatic consumption logs from description/search/review.

Local, ignored screenshots: `ReviewArtifacts/22-ai-description-database-choice.png`, `23-explicit-product-search.png`, `24-product-portion-confirmation.png`. These are test-hosted SwiftUI captures with synthetic values, not claims of physical-device or live AI verification. No new IPA/release is part of this change.

## Affected files

- New domain/service: `Services/MealFoodDatabase.swift`, `Services/OpenFoodFactsSearchService.swift`.
- Coordinator/shared choices: `Views/Logging/MealAnalysisFlow.swift`; text/photo flow views.
- Existing detail reader: `Services/BarcodeLookupService.swift` (source-only mode and pacing).
- USDA brand correction handling: `Services/AINutritionService.swift`, `Services/NutritionAnalysisResult.swift`.
- Confirmation attribution and Food Database settings; checked-in Xcode project source entries; README and this research note.
- New tests: `MealDatabaseChoiceTests.swift`, `OpenFoodFactsSearchTests.swift`, `OFFFixtures`; additional `MealReviewRenderingTests` captures.

## Manual acceptance

1. Describe a meal, choose each database, run AI ingredient review, correct grams/brand/preparation, and continue. Both choices should retain the edits.
2. With no AI configuration, use Enter ingredients without AI; confirm unspecified weights block lookup and “mac and cheese” stays one editable row.
3. Photograph a meal, read the returned description and uncertainty, edit ingredients, then choose USDA or Open Food Facts. No database should run before Continue.
4. In Open Food Facts, refine a name/brand, reject a wrong product, choose the correct one, inspect its reference and selected amount, and explicitly confirm every ingredient.
5. Verify cooked-weight and mL-only records require correction. Toggle offline/online and Retry without losing review state.
6. Separately save and log; reopen offline, use a fractional serving and compare the historical snapshot. Export/import into a test store and verify source IDs and duplicates.
7. Replace a photo while reviewing; its old analysis must disappear. Cancel during a lookup; a late response must not resume the abandoned workflow.
