#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/verify_resources.py
if [[ "$(uname -s)" == Darwin ]]; then
  xcodebuild -version
  swift --version
  test "$(xcodebuild -version | head -1)" = 'Xcode 16.4'
  xcrun --sdk iphoneos --show-sdk-version
  xcodebuild -list -project ChaiTrade.xcodeproj
fi
