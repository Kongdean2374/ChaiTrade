#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root="$PWD"
mkdir -p build/logs dist
test ! -e dist/ChaiTrade-unsigned.ipa
xcodebuild build -project ChaiTrade.xcodeproj -scheme ChaiTrade \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' \
  2>&1 | tee build/logs/device-build.log
app_path="$repo_root/build/DerivedData/Build/Products/Release-iphoneos/ChaiTrade.app"
bash scripts/verify_artifact.sh "$app_path"
package_dir="$(mktemp -d "$repo_root/build/package.XXXXXX")"
mkdir "$package_dir/Payload"
ditto "$app_path" "$package_dir/Payload/ChaiTrade.app"
(cd "$package_dir" && /usr/bin/zip -qry "$repo_root/dist/ChaiTrade-unsigned.ipa" Payload)
unzip -t dist/ChaiTrade-unsigned.ipa
(cd dist && shasum -a 256 ChaiTrade-unsigned.ipa > ChaiTrade-unsigned.ipa.sha256)
python3 scripts/build_info.py
cp build/logs/core-tests.log dist/core-tests.log
cp build/logs/ui-tests.log dist/ui-tests.log
echo '未簽名 IPA 已封裝；仍須另行簽署與實機驗證。'
