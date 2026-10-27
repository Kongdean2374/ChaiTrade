#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
CHAI_STRESS=1 CHAI_REPORT_DIR="$PWD/build/logs" \
  swift test --package-path Packages/ChaiTradeCore -c release --filter stressHistory100000 \
  2>&1 | tee build/logs/stress-tests.log
