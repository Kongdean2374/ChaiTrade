#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
simulator_id="$(python3 scripts/prepare_simulator.py)"
common=(-project ChaiTrade.xcodeproj -scheme ChaiTrade -destination "platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)" -derivedDataPath build/UISimulator
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='' ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)")
xcodebuild build-for-testing "${common[@]}" 2>&1 | tee build/logs/navigation-build.log
xcodebuild test-without-building "${common[@]}" -resultBundlePath build/NavigationFlowTests.xcresult \
  -only-testing:ChaiTradeUITests/NavigationFlowTests \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  2>&1 | tee build/logs/navigation-tests.log
