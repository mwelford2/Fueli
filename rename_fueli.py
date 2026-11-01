#!/usr/bin/env python3
"""Rename the Fueli (formerly CalClone) iOS source project and bundle ID.

Usage, from any directory:
  python3 rename_fueli.py --repo /path/to/Fueli             # preview
  python3 rename_fueli.py --repo /path/to/Fueli --apply     # make changes

This changes SOURCE ONLY plus stale source-file links in apps.json.
It preserves apps.json's existing bundle ID and release download links,
and never modifies an already-released IPA.
"""

import argparse
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

OLD_BUNDLE_ID = "com.matteowelford.calclone"
NEW_BUNDLE_ID = "com.welford.fueli"

# Specific identifiers must precede the general CalClone -> Fueli substitutions.
REPLACEMENTS = (
    ("com.welford.CalCloneTests", "com.welford.fueli.tests"),
    (OLD_BUNDLE_ID, NEW_BUNDLE_ID),
    ("CalClone", "Fueli"),
    ("calclone", "fueli"),
    ("CALCLONE", "FUELI"),
)

# Old releases still have the old bundle ID. Only update links to files
# renamed in the source tree; preserve their bundle ID, versions and IPA URLs.


def run_git(repo: Path, *args: str) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace").strip())
    return result.stdout


def replace_text(original: str, relative_path: str) -> str:
    if relative_path == "apps.json":
        # The current app is still the old bundle ID. The icon/docs live in
        # the renamed source tree, so fix their paths without changing the ID.
        return original.replace("CalClone/", "Fueli/")
    modified = original
    for old, new in REPLACEMENTS:
        modified = modified.replace(old, new)

    # On the FIRST NEW release, migrate the feed from the old app identity to
    # the new one, and remove old-version links that cannot match the new ID.
    # Do not publish or modify the actual apps.json now.
    if relative_path == "release.sh":
        anchor = ".apps[0].version = $version |"
        if anchor not in modified:
            raise RuntimeError("release.sh format changed; cannot safely update future feed handling")
        if ".apps[0].bundleIdentifier =" not in modified:
            modified = modified.replace(anchor, (
                '.apps[0].versions = (if .apps[0].bundleIdentifier == "com.welford.fueli" '
                'then .apps[0].versions else [] end) |\n'
                '  .apps[0].bundleIdentifier = "com.welford.fueli" |\n'
                '  .apps[0].iconURL |= gsub("/CalClone/"; "/Fueli/") |\n'
                '  ' + anchor
            ), 1)
    return modified


def new_name(name: str) -> str:
    return name.replace("CalClone", "Fueli").replace("calclone", "fueli")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="Fueli repository root (default: current directory)")
    parser.add_argument("--apply", action="store_true", help="Perform changes; default is a dry-run preview")
    args = parser.parse_args()
    repo = args.repo.expanduser().resolve()

    essentials = (
        "CalClone.xcodeproj/project.pbxproj",
        "CalClone.xcodeproj/xcshareddata/xcschemes/CalClone.xcscheme",
        "CalClone/Resources/CalClone.entitlements",
        "CalClone/Resources/CalClone-Free.entitlements",
        "CalClone/App/CalCloneApp.swift",
        "CalCloneTests/CalCloneTests.swift",
        "project.yml",
        "release.sh",
        "apps.json",
    )
    missing = [p for p in essentials if not (repo / p).is_file()]
    if missing:
        raise RuntimeError("Not the expected unrenamed Fueli source tree. Missing: " + ", ".join(missing))

    entitlements = plistlib.loads((repo / "CalClone/Resources/CalClone.entitlements").read_bytes())
    if entitlements.get("com.apple.developer.healthkit") is not True:
        raise RuntimeError("HealthKit not enabled in source entitlements; refusing to continue")

    if run_git(repo, "status", "--porcelain", "--untracked-files=no").strip():
        raise RuntimeError(
            "Tracked files have uncommitted changes. Commit/stash them first, "
            "then rerun the rename to avoid mixing or overwriting work."
        )

    paths = [Path(p.decode("utf-8")) for p in run_git(repo, "ls-files", "-z").split(b"\0") if p]
    changes = []
    for rel in paths:
        file = repo / rel
        if file.is_symlink() or not file.is_file():
            continue
        raw = file.read_bytes()
        if b"\0" in raw:
            continue  # Images, binary resources, etc.
        try:
            content = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        updated = replace_text(content, rel.as_posix())
        if updated != content:
            changes.append((file, updated))

    # Rename tracked paths and their containing directories, deepest first.
    rename_paths = set()
    for rel in paths:
        current = rel
        while current != Path("."):
            if new_name(current.name) != current.name:
                rename_paths.add(current)
            current = current.parent
    rename_paths = sorted(rename_paths, key=lambda p: (len(p.parts), str(p)), reverse=True)
    for rel in rename_paths:
        old = repo / rel
        dest = old.with_name(new_name(old.name))
        if not old.exists():
            raise RuntimeError(f"Expected source to exist: {old}")
        if dest.exists():
            raise RuntimeError(f"Cannot rename {old}: destination already exists: {dest}")

    print(f"Repository: {repo}")
    print(f"Bundle ID:  {OLD_BUNDLE_ID}  ->  {NEW_BUNDLE_ID}")
    print(f"Edit {len(changes)} text files; rename {len(rename_paths)} file/directory paths.")
    for path, _ in changes:
        print(f"  EDIT   {path.relative_to(repo)}")
    for rel in rename_paths:
        print(f"  RENAME {rel} -> {rel.with_name(new_name(rel.name))}")
    print("Preserve existing apps.json bundle ID and release links; update only renamed asset/document paths.")
    print("Preserve HealthKit entitlement; no automatic signing or publishing.")

    if not args.apply:
        print("\nPREVIEW ONLY. Add --apply to make these changes.")
        return 0

    for path, updated in changes:
        path.write_bytes(updated.encode("utf-8"))
    for rel in rename_paths:
        source = repo / rel
        source.rename(source.with_name(new_name(source.name)))

    pbx = (repo / "Fueli.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    yml = (repo / "project.yml").read_text(encoding="utf-8")
    scheme = repo / "Fueli.xcodeproj/xcshareddata/xcschemes/Fueli.xcscheme"
    ent = repo / "Fueli/Resources/Fueli.entitlements"
    assert scheme.is_file(), "Renamed Xcode scheme missing"
    assert (repo / "Fueli/App/FueliApp.swift").is_file(), "Renamed Swift app entrypoint missing"
    assert (repo / "FueliTests/FueliTests.swift").is_file(), "Renamed test target missing"
    assert 'PRODUCT_BUNDLE_IDENTIFIER = com.welford.fueli;' in pbx
    assert 'CODE_SIGN_ENTITLEMENTS = Fueli/Resources/Fueli.entitlements;' in pbx
    assert 'PRODUCT_BUNDLE_IDENTIFIER: com.welford.fueli' in yml
    assert plistlib.loads(ent.read_bytes()).get('com.apple.developer.healthkit') is True
    feed = (repo / "apps.json").read_text(encoding="utf-8")
    assert OLD_BUNDLE_ID in feed  # Do NOT advertise old IPA as the new app.
    assert '"bundleIdentifier": "com.welford.fueli"' not in feed

    print("\nSource rename complete; HealthKit entitlement verified.")
    print("Next, on macOS:")
    print("  plutil -lint Fueli.xcodeproj/project.pbxproj")
    print("  xcodebuild -list -project Fueli.xcodeproj")
    print("  xcodebuild -project Fueli.xcodeproj -scheme Fueli -configuration Debug \\")
    print("    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \\")
    print("    CODE_SIGNING_ALLOWED=NO build")
    print("  git status --short")
    print("\nImportant: GitHub release v1.0.12 and apps.json STILL describe the OLD app ID.")
    print("apps.json asset/docs paths were updated; its old release metadata remains intact.")
    print("A NEW compiled IPA and a HealthKit-enabled Apple App ID/profile are required.")
    print("Before using release.sh, inspect ~/bin/make-ipa.sh for old hardcoded project paths.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, AssertionError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
