#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
simulator_id="$(python3 scripts/prepare_simulator.py)"
destination="platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)"
xcodebuild test -project ChaiTrade.xcodeproj -scheme ChaiTrade \
  -destination "$destination" -resultBundlePath build/UITests.xcresult \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='' \
  ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)" \
  2>&1 | tee build/logs/ui-tests.log
