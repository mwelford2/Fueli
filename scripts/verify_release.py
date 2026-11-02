#!/usr/bin/env python3
"""Fail closed before publication; local evidence contains no credentials.

Evidence schema: {version:1, sourceCommit:HEAD, ipaSHA256:hex,
 resultBundles:[absolute .xcresult paths],
 physicalChecks:{cameraScanning:"user-confirmed", appleHealth:"user-confirmed"}}
Populate physicalChecks only after actual device acceptance, never from mocks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DEVICE_CHECKS = ("cameraScanning", "appleHealth")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_summary(summary):
    require(summary.get("result") == "Passed", "A required test run did not pass")
    require(summary.get("totalTestCount", 0) > 0, "Empty test runs are not evidence")
    for field in ("failedTests", "skippedTests", "expectedFailures"):
        require(summary.get(field) == 0, f"Required test run contains {field}")
    require(summary.get("passedTests") == summary.get("totalTestCount"), "Incomplete test execution")


def passed_nodes(tree):
    result = set()
    def visit(node):
        if node.get("nodeType") == "Test Case" and node.get("result") == "Passed":
            result.add(node.get("nodeIdentifier", ""))
        for child in node.get("children", []):
            visit(child)
    for node in tree.get("testNodes", []):
        visit(node)
    return result


def source_fingerprint():
    names = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--",
        "Fueli", "FueliTests", "FueliUITests", "Fueli.xcodeproj", "project.yml"], cwd=ROOT).decode().split("\0")
    digest = hashlib.sha256()
    for name in sorted(set(names)):
        path = ROOT / name
        if not name or not path.is_file() or path.suffix == ".md" or name.endswith(".example.xcconfig"):
            continue
        digest.update(name.encode() + b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def verify(evidence_path, ipa):
    evidence = json.loads(evidence_path.read_text())
    require(evidence.get("version") == 1, "Unsupported release evidence version")
    require(evidence.get("sourceFingerprint") == source_fingerprint(), "Build/test source changed after verification began")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    require(evidence.get("sourceCommit") == head, "Test evidence is for another source commit")
    status = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True)
    require(not status.strip(), "Commit and review all source changes before publication")
    require(evidence.get("ipaSHA256") == hashlib.sha256(ipa.read_bytes()).hexdigest(), "IPA differs from tested candidate")
    with zipfile.ZipFile(ipa) as archive:
        plist_paths = [n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        require(len(plist_paths) == 1, "Expected one application in IPA")
        info = plistlib.loads(archive.read(plist_paths[0]))
        require(info.get("CFBundleIdentifier") == "com.welford.fueli", "Wrong application bundle ID")
        version = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', (ROOT / "project.yml").read_text())
        require(version is not None and info.get("CFBundleShortVersionString") == version.group(1), "IPA version differs from source configuration")
        require(not info.get("USDA_API_KEY"), "IPA contains a bundled USDA credential")
    checks = evidence.get("physicalChecks", {})
    require(all(checks.get(k) == "user-confirmed" for k in DEVICE_CHECKS), "Physical iPhone acceptance is incomplete")
    bundles = evidence.get("resultBundles", [])
    require(bool(bundles), "Missing actual Xcode result bundles")
    passed = set()
    for bundle in bundles:
        def result(kind):
            return json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", kind, "--path", bundle, "--compact"]))
        validate_summary(result("summary"))
        passed |= passed_nodes(result("tests"))
    ui_source = (ROOT / "FueliUITests/AppJourneyTests.swift").read_text()
    required = {"AppJourneyTests/" + n + "()" for n in re.findall(r"func\s+(test\w+)\(", ui_source)}
    live_source = (ROOT / "FueliTests/ReleaseLiveTests.swift").read_text()
    required |= {"ReleaseLiveTests/" + n + "()" for n in re.findall(r"func\s+(required\w+)\(", live_source)}
    require(required <= passed, "Required UI or live API tests were excluded")
    # Derive every declared Swift Testing method from source so adding a new test
    # automatically makes it required. Argument cases are checked by the result
    # summary's no-skip/no-failure rule; UI methods above retain their suite IDs.
    declared = set()
    for source in (ROOT / "FueliTests").rglob("*.swift"):
        text = source.read_text()
        for annotation in re.finditer(r"@Test\b", text):
            method = re.search(r"\bfunc\s+(\w+)\s*\(", text[annotation.end():])
            require(method is not None, "Cannot enumerate a Swift Testing declaration")
            declared.add(method.group(1))
        declared.update(re.findall(r"func\s+(test\w+)\(", text))
    executed = {n.split("/")[-1].split("(")[0] for n in passed}
    require(declared <= executed, "Unit tests were excluded: " + ", ".join(sorted(declared - executed)))
    # Unit suites must also have run; successful selected UI tests alone cannot release.
    for suite in ("NutritionSafetyTests", "PersistenceActionTests", "RigorousDomainTests", "AIWireContractTests", "MealDatabaseChoiceTests"):
        require(any(n.startswith(suite + "/") for n in passed), f"Missing unit suite: {suite}")
    return len(passed)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--ipa", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(f"Release evidence accepted: {verify(args.evidence, args.ipa)} test identifiers passed.")
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Release held: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
