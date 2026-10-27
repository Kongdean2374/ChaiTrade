#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
destination="platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5,arch=$(uname -m)"
xcodebuild test -project ChaiTrade.xcodeproj -scheme ChaiTrade \
  -destination "$destination" -resultBundlePath build/UITests.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)" \
  2>&1 | tee build/logs/ui-tests.log
