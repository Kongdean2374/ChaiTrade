#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_resources.py
python3 scripts/security_scan.py
if [[ "$(uname -s)" == Darwin ]]; then
  xcodebuild -version
  swift --version
  test "$(xcodebuild -version | head -1)" = 'Xcode 26.2'
  xcrun --sdk iphoneos --show-sdk-version
  xcodebuild -list -project ChaiTrade.xcodeproj
fi

node scripts/test_chart_web.js
