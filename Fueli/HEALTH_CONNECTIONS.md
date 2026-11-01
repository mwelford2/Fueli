# Fitness health connections

Implemented via the iOS HealthKit store. Vendor apps write data into Apple Health; Fueli requests read-only Active and Resting Energy access. There is no direct Garmin/Google/Oura/WHOOP/Strava OAuth implementation, no vendor credential collection, and no paid intermediary. Connection guides and real source discovery are available from Settings → Health Connections and setup.

## Official references checked 2026-10-30

- [Garmin: sharing Connect data with Apple Health](https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA). Enable available Health sharing categories in Garmin Connect and sync the device. The exported categories/history depend on the source app; the UI asks users to inspect actual shared data rather than promising a full export.
- [Garmin Health API](https://developer.garmin.com/gc-developer-program/health-api/): evaluation follows approval and commercial use requires licensing. Fueli does not simulate a direct account connection without this infrastructure.
- [Google Health: connect third-party devices and apps](https://support.google.com/googlehealth/answer/14236613?hl=en): iPhone integrations use Apple Health; provider metric availability varies. The app guide does not assert that every Fitbit/Pixel Watch metric becomes a writable HealthKit energy sample. Android [Health Connect](https://developer.android.com/health-and-fitness/health-connect/availability) cannot be queried by an iOS app.
- [Oura's Apple Health guide](https://ouraring.com/blog/apple-health/): active energy can be exported. Active energy alone excludes resting needs, so cannot establish Fueli's total-energy baseline.
- [WHOOP Apple Health integration](https://support.whoop.com/s/article/Apple-Health-Integration?language=en_US): supports exporting active energy and workouts among other metrics. Do not confuse resting heart rate with resting energy.
- [Strava Apple Health integration](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava): Send to Health exports activity data/calories; workout energy is not an all-day total. Source sync restrictions apply.
- [Apple: manage data sources and apps](https://support.apple.com/en-us/108779). Source order and permissions are controlled by the user in Health.

Apple HKSourceQuery API documentation was retrieved with Context7. Source queries return sources with matching readable samples; they do not expose vendor account authentication state or prove read permission was granted.

## Data behavior

Queries cover the last 14 days for active and resting energy. Source identity uses HealthKit's bundle identifier, never a guessed provider name. Duplicate appearances across types are merged by identity, preserving which energy types were observed. Identical display names with different identities stay separate. No-data states remain unconfirmed rather than labeled disconnected or authorized. Requests are user-triggered; already enabled connections can refresh on opening or foregrounding the screen. A refresh control is available after the user syncs an app.

Calorie arithmetic stays in the existing HealthKit aggregation path: active + resting only once per eligible completed day, with source merging left to HealthKit. No per-provider total is added on top of the merged statistics. A successful baseline update stores the average and its dates/count in the existing profile fields. Missing/partial history leaves the previous baseline intact. Disconnect instructions explain how to revoke Health permission and separately stop using a saved baseline in Goals & Profile; revocation does not falsely claim to delete historical samples.

## Verification and manual checks

Tests cover source identity merging, preservation of active/resting flags, distinct sources with identical names, empty results, and provider help configuration. Simulator testing cannot authenticate a Garmin/Google account, verify vendor exports, or validate real wear-time coverage.

On iPhone: connect a provider in its own app; allow writing energy to Health; sync the device; enable Fueli read access; refresh observed sources and compare with Health's Data Sources & Access. Test denied read access and missing resting energy. Update a baseline only after enough eligible days exist. Confirm insufficient history retains the current plan, and repeat with overlapping sources without summing vendor totals. Revoke permission in Health and verify that Fueli no longer observes those samples; disable the saved baseline explicitly if desired.

Executed: `xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -sdk iphonesimulator -configuration Debug -derivedDataPath /private/tmp/fueli-nutrition-build CODE_SIGNING_ALLOWED=NO build` (passed), then `xcodebuild -project ../Fueli.xcodeproj -scheme Fueli -destination 'platform=iOS Simulator,id=9EDE4995-25DA-4E2F-9C4A-67E57E644D0F' -derivedDataPath /private/tmp/fueli-nutrition-build CODE_SIGNING_ALLOWED=NO test` (passed). Result: `/private/tmp/fueli-nutrition-build/Logs/Test/Test-Fueli-2026.10.30_14-10-37--0400.xcresult`. No live vendor sync verification was performed. `git diff --check` passed.

Approved simulator follow-up, 2026-10-31: explicitly allowed Fueli read access to Active Energy and Resting Energy through the native Health prompts. Source discovery and baseline queries completed without errors; no readable energy history was present (0 active/resting/paired days). The existing plan was retained. This is a simulator empty-store check, not validation of physical Watch/vendor sync or the user's iPhone data. No write permissions were granted.
