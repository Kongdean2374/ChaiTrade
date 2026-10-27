#!/usr/bin/env bash
set -euo pipefail
app_path="${1:?提供 device .app 路徑}"
test -d "$app_path"
test -f "$app_path/ChaiTrade"
test -f "$app_path/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleSupportedPlatforms:0' "$app_path/Info.plist")" = iPhoneOS
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$app_path/Info.plist")" = 18.0
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")" = org.chaitrade.app
xcrun lipo -info "$app_path/ChaiTrade" | grep -q arm64
xcrun vtool -show-build "$app_path/ChaiTrade" | grep -q 'platform IOS'
test -s "$app_path/ChartWeb/lightweight-charts.js"
test -s "$app_path/Licenses/LightweightCharts-LICENSE"
test -s "$app_path/Assets.car"
if find "$app_path" -type f \( -name '*.p12' -o -name '*.p8' -o -name '*.mobileprovision' -o -name '*.sqlite' -o -name '*.chaitrade' \) | grep -q .; then
  echo '產物包含不允許的個人資料或憑證' >&2; exit 1
fi
signature="$(codesign -dv --verbose=4 "$app_path" 2>&1 || true)"
if [[ "$signature" == *'Authority='* || "$signature" == *'TeamIdentifier='* && "$signature" != *'TeamIdentifier=not set'* ]]; then
  echo '產物含裝機身分簽署，預期為未簽名或 ad-hoc' >&2;exit 1
fi
printf '%s\n' "$signature"
