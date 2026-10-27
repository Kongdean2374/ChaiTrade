#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
(cd Packages/ChaiTradeCore && swift test) 2>&1 | tee build/logs/core-tests.log
