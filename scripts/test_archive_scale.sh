#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
export CHAI_ARCHIVE_SCALE=1
export CHAI_REPORT_DIR="$PWD/build/logs"
swift test --package-path Packages/ChaiTradeCore -c release --filter archiveOver512MBPreservesEveryAttachmentWithBoundedWorkingMemory 2>&1 | tee build/logs/archive-scale-tests.log
