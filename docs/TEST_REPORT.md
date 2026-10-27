# Test report

2026-10-27. Requirements and thresholds remain in REQUIREMENTS.md. TEST_MATRIX.md records acceptance scope; unimplemented/unexecuted cases are not counted as passes.

## Completed Apple T45 correction

[Run 40466253220](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40466253220), commit 6296ddcbead29a41ea55b4808ec3c68a885464eb: core, required Release 100,000-fill gate, iPhoneOS unsigned IPA verification and all three UI tests passed. UI cases cover local market order/position, onboarding/navigation/relaunch, and pending A/B switching requiring cold launch while retaining the offline position.

Apple measurements: hot load 0.0861 s; page-100 p95 0.00696 s; order-write p95 0.0261 s; full CSV 0.3873 s. 30 samples per p95. Bulk import 14.01 s and full integrity reconstruction 14.37 s are explicit background operations, not screen loads.

## Current feature batch: local evidence, Apple rerun pending

55 ordinary core functions pass locally. The Swift Testing ordinary summary includes two disabled opt-in functions; those are executed separately, not counted as ordinary passes. Release with CHAI_STRESS=1 executes the full suite plus T45, and the production Coinbase test was separately executed with CHAI_LIVE=1 and system CA trust. Synthetic provider fixtures cover all quote adapters; no credentialed provider is declared live-verified.

The latest Release T45 preserves 100,000 fills/orders and 200,002 ledger entries, compares all CSV bytes against canonical full-state export, restores all records/balances from a compressed backup, checks exact period/cycle counts, and measures 30 actual matched order writes while an independent full snapshot reads concurrently. Local measurements are in STRESS_REPORT.json: hot load 0.0350 s; page p95 0.00226 s; order p95 0.0353 s; CSV 0.1136 s; analytics 0.00783 s. Full integrity reconstruction remains 8.21 s and bulk import 10.56 s.

Hard gates remain 3 s cold load, 300 ms page interaction p95 and 150 ms local order-feedback p95, with additional 3 s full CSV and 3 s full analytics gates. These are Linux/Apple CI measurements, not signed iPhone claims. A failed gate blocks IPA upload. The earlier CSV 5.16 s and analytics 3.35 s failures were fixed, not waived.

Added tests cover schema-1/schema-2 migration rollback/retry, failed append atomicity, stable equal-time cursors, bounded decompression, partial/flip cycle accounting, every-five-second OHLC equivalence, calendar/DST/leap months, history paging, journal/notification/preference backup isolation, maintenance tokens, queued-request freshness, negative NAV drawdown and missing-valuation chart segments.

Live production Coinbase adapter: actual ticker, level2 snapshot and candles passed; market values were not retained. Binance's regional HTTP 451 and missing entitlements for the other providers remain external verification limits. Logs/xcresult and machine-readable metrics are retained in Actions artifacts. The latest source batch still requires a successful Apple build/UI run before its IPA can be published.
