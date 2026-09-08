---
name: build-release
description: Build and publish a new Fueli (CalClone) release from this repo — archive the app, package the IPA, create the GitHub release, and commit. Use when the user asks to "cut a release", "build a new release", "ship a new version", or bump + release Fueli.
---

# Build a Fueli release

Only for the CalClone / Fueli project at `/Users/matteowelford/Documents/CalAIClone`. Perform the steps in order.

## Prerequisites

- `gh` and `jq` installed and authenticated (`release.sh` checks this).
- `CalClone/Secrets.xcconfig` present with a valid `USDA_API_KEY` (untracked, gitignored — never commit it).
- A clean-ish working tree; know what version you're shipping.

## Steps

1. **Bump the version.** Edit `MARKETING_VERSION` in `CalClone.xcodeproj/project.pbxproj`. There are three app-target configs (Debug, Free, Release) — bump all three to the same value. Confirm the target version with the user if unclear; default to a patch bump from the current value.

2. **Archive the app** with xcodebuild (do not rely on a stale Xcode archive):
   ```
   xcodebuild archive \
     -project CalClone.xcodeproj \
     -scheme CalClone \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/CalClone-<version>.xcarchive \
     -allowProvisioningUpdates
   ```
   Wait for `** ARCHIVE SUCCEEDED **`.

3. **Verify the archive** before packaging:
   ```
   ARCHIVE=$(ls -td ~/Library/Developer/Xcode/Archives/*/*.xcarchive | head -1)
   APP="$ARCHIVE/Products/Applications/CalClone.app"
   /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist"   # == <version>
   /usr/libexec/PlistBuddy -c "Print :USDA_API_KEY" "$APP/Info.plist"                 # == expected key
   ```

4. **Package the IPA:** run `~/bin/make-ipa.sh`. It picks the most recent archive and writes `Fueli.ipa` to the project root.

5. **Publish the release:** run `./release.sh "<release notes>"`. This re-runs `make-ipa.sh`, reads the version from the IPA, creates the GitHub release (`v<version>` on `mwelford2/Fueli`) with the IPA attached, updates `apps.json`, then commits and pushes `apps.json` as `Release v<version>`. If the tag already exists it will prompt to replace it.

6. **Commit remaining changes.** `release.sh` only commits `apps.json`. Commit the version bump separately:
   ```
   git add CalClone.xcodeproj/project.pbxproj
   git commit -m "Bump MARKETING_VERSION to <version>"
   git push
   ```
   Do **not** stage `CalClone/Secrets.xcconfig` — it is gitignored and holds live keys.

## Notes

- `release.sh` targets repo `mwelford2/Fueli`; the AltStore source is `apps.json` at the repo root.
- Commit message attribution follows the session's current attribution guidance.
- If archiving fails on signing, ensure the Apple Development identity / provisioning is available and `-allowProvisioningUpdates` is passed.
