#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
simulator_id="$(python3 scripts/prepare_simulator.py)"
# The same job already compiled all app and XCTest targets. This supplements full regressions.
set -o pipefail
xcodebuild test-without-building -project ChaiTrade.xcodeproj -scheme ChaiTrade \
  -destination "platform=iOS Simulator,id=$simulator_id,arch=$(uname -m)" -derivedDataPath build/UISimulator \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='' ONLY_ACTIVE_ARCH=YES ARCHS="$(uname -m)" \
  -resultBundlePath build/ProductFocused.xcresult \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testContractPositionHasAnExplicitReduceOnlyCloseJourney \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testOfflineCatalogSearchSelectsRealETFWithoutChangingAccount \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testFinancialHistoryEmptyCategoriesKeepAccountAndPageBoundaries \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testCompleteJSONFileExportRemainsShareableAfterRestartWithoutChangingAccount \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testChartLandscapeAndReturnKeepsSelectedProduct \
  -only-testing:ChaiTradeUITests/ProductExperienceTests/testOfflineThreeActionDiscoveryAndFullStockJourney \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -maximum-test-execution-time-allowance 120 \
  2>&1 | tee build/logs/product-focused-tests.log
