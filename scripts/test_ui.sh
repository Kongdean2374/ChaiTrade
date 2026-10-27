#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
simulator_id="$(python3 scripts/prepare_simulator.py)"
destination="platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)"
common=(-project ChaiTrade.xcodeproj -scheme ChaiTrade -destination "$destination" -derivedDataPath build/UISimulator
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=''
  ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)")
xcodebuild build-for-testing "${common[@]}" 2>&1 | tee build/logs/ui-build.log
# Diagnose the previously failing order flow first. Full acceptance remains mandatory below.
xcodebuild test-without-building "${common[@]}" -resultBundlePath build/UIOrderFocused.xcresult \
  -only-testing:ChaiTradeUITests/InteractionTests/testRapidOrderConfirmationAndCancelDebitExactlyOnce \
  -parallel-testing-enabled NO -test-iterations 2 -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  2>&1 | tee build/logs/ui-focused-order.log
xcodebuild test-without-building "${common[@]}" -resultBundlePath build/UITests.xcresult \
  -parallel-testing-enabled NO -test-iterations 2 -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  2>&1 | tee build/logs/ui-tests.log
