#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${FUELI_TEST_DESTINATION:?Set FUELI_TEST_DESTINATION to an installed iOS simulator destination}"
SECRETS="${FUELI_TEST_SECRETS:-$PWD/.fueli-test-secrets.json}"
[[ -r "$SECRETS" ]] || { echo 'Missing private test JSON. Copy fueli-test-secrets.example.json and configure it locally.'; exit 1; }
RESULT_ROOT=$(mktemp -d /private/tmp/fueli-verification.XXXXXX)
xcodegen generate
export TEST_RUNNER_FUELI_RELEASE_LIVE=1
export TEST_RUNNER_FUELI_LIVE_USDA_TESTS=1
export TEST_RUNNER_FUELI_LIVE_OFF_TESTS=1
export TEST_RUNNER_FUELI_LIVE_SECRETS_PATH="$SECRETS"
echo "Results: $RESULT_ROOT"
xcodebuild -project Fueli.xcodeproj -scheme Fueli -destination "$FUELI_TEST_DESTINATION" \
  -derivedDataPath "$RESULT_ROOT/DerivedData" -resultBundlePath "$RESULT_ROOT/AllTests.xcresult" \
  -parallel-testing-enabled NO test
# Exit 0 alone is insufficient: reject empty/skipped/expected-failure runs too.
python3 - "$RESULT_ROOT/AllTests.xcresult" <<'PY'
import json, subprocess, sys
sys.path.insert(0, 'scripts')
from verify_release import validate_summary
summary = json.loads(subprocess.check_output(['xcrun','xcresulttool','get','test-results','summary','--path',sys.argv[1],'--compact']))
validate_summary(summary)
print('All automated checks passed with no skips. Physical acceptance remains separate.')
PY
