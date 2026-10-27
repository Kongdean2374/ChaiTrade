# Test report

2026-10-27. Requirements and thresholds remain in REQUIREMENTS.md. TEST_MATRIX.md records acceptance scope; unimplemented/unexecuted cases are not counted as passes.

## Completed Apple T45 correction

[Run 40466253220](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40466253220), commit 6296ddcbead29a41ea55b4808ec3c68a885464eb: core, required Release 100,000-fill gate, iPhoneOS unsigned IPA verification and all three UI tests passed. UI cases cover local market order/position, onboarding/navigation/relaunch, and pending A/B switching requiring cold launch while retaining the offline position.

Apple measurements: hot load 0.0861 s; page-100 p95 0.00696 s; order-write p95 0.0261 s; full CSV 0.3873 s. 30 samples per p95. Bulk import 14.01 s and full integrity reconstruction 14.37 s are explicit background operations, not screen loads.

## Current feature batch: local evidence, Apple rerun pending

65 ordinary core functions pass locally. The Swift Testing ordinary summary includes two disabled opt-in functions; those are executed separately, not counted as ordinary passes. Release with CHAI_STRESS=1 executes the full suite plus T45, and the production Coinbase test was separately executed with CHAI_LIVE=1 and system CA trust. Synthetic provider fixtures cover all quote adapters; no credentialed provider is declared live-verified.

The latest Release T45 preserves 100,000 fills/orders and 200,002 ledger entries, compares all CSV bytes against canonical full-state export, restores all records/balances from a compressed backup, checks exact period/cycle counts, and measures 30 actual matched order writes while an independent full snapshot reads concurrently. Local measurements are in STRESS_REPORT.json: hot load 0.0350 s; page p95 0.00226 s; order p95 0.0353 s; CSV 0.1136 s; analytics 0.00783 s. Full integrity reconstruction remains 8.21 s and bulk import 10.56 s.

Hard gates remain 3 s cold load, 300 ms page interaction p95 and 150 ms local order-feedback p95, with additional 3 s full CSV and 3 s full analytics gates. These are Linux/Apple CI measurements, not signed iPhone claims. A failed gate blocks IPA upload. The earlier CSV 5.16 s and analytics 3.35 s failures were fixed, not waived.

Added tests cover schema-1/schema-2 migration rollback/retry, failed append atomicity, stable equal-time cursors, bounded decompression, partial/flip cycle accounting, every-five-second OHLC equivalence, calendar/DST/leap months, history paging, journal/notification/preference backup isolation, maintenance tokens, queued-request freshness, negative NAV drawdown and missing-valuation chart segments.

Live production Coinbase adapter: actual ticker, level2 snapshot and candles passed; market values were not retained. Binance's regional HTTP 451 and missing entitlements for the other providers remain external verification limits. Logs/xcresult and machine-readable metrics are retained in Actions artifacts. The latest source batch still requires a successful Apple build/UI run before its IPA can be published.

## Automatic offline lifecycle and stricter replay evidence

B fixed-clock long/short carry, daily settlement and final expiry are tested across bounded checkpoints and restart using complete canonical state bytes. String sets now serialize in sorted order without changing their JSON array format. Isolated fees consume free funds before their own margin and preserve negative debt; cross collateral excludes other-currency isolated wallets. The new tests keep exact Decimal expected values. A's entitled event feeds remain unverified.

Run 40470960600 passed core and required T45 but failed native compilation on SDK notification object sendability; no IPA was uploaded from that run. The adapter now copies primitive permission/identifier values inside system callbacks, preserving strict concurrency checks. The navigation delegate callback also matches the SDK's actor/sendable annotations. Native UI verification remains pending until the new run completes.

Latest local full Release run: CHAI_STRESS=1 and CHAI_LIVE=1 together, all 62 functions executed and passed with no skipped tests. This includes the real Coinbase adapter and 100,000-fill/analytics/concurrent-backup gates. Latest timing values are in STRESS_REPORT.json. DST missing local time resolves to the next valid time and repeated local time to the first occurrence, with stable per-day event IDs. The Apple-native fix awaits the next workflow; a failed prior native build is not counted as UI success.

## Strengthened T45: 100,000 fills plus 100,001 equity points

An additional realistic curve workload exposed a remaining failure: old hot equity held 100,001 points and matched order-write p95 reached 0.5878 s. That failure was not waived. Schema 4 now appends immutable equity rows and stores bounded prefix return/drawdown state. Hot equity is capped at 1,000 points; older values and normalized returns are pageable. Full snapshots and compressed backups retain all 100,001 points. Tests also cover prefix return/drawdown across deposits, immutable history, schema-3 migration interruption/retry, simulation-time initial capital, and same-timestamp trade fees.

Latest full local Release run enables both CHAI_STRESS=1 and CHAI_LIVE=1: all 66 tests executed and passed, zero skipped. Strengthened T45 timings: hot load 0.0455 s; page p95 0.00259 s; matched writes p95 0.0492 s while a full reader runs; CSV 0.1197 s; analytics 0.0157 s. Bulk import 14.35 s and full integrity reconstruction 9.45 s remain explicit background operations. Original 3 s / 300 ms / 150 ms thresholds and the additional 3 s report gates are unchanged.

Apple run 40475247267 compiled the native app successfully and passed three UI cases. The screenshot/journal case reached save but did not find its offscreen export row; the unchanged export-button assertion now scrolls the lazy form into view and also rejects operation-error alerts. That failed run did not publish an IPA. The latest schema-4 source requires the new full Apple run.

Final local regression before the native rerun: all 67 Release tests passed with stress and real Coinbase enabled, zero skipped. The additional test pages 160+160 offline stock candles across market closure/weekend boundaries without duplicate bars. Latest local strengthened T45: load 0.0462 s; page p95 0.00247 s; write p95 0.0432 s; CSV 0.1196 s; analytics 0.0153 s; full reconstruction 9.43 s; bulk import 12.02 s.

Apple run 40478300516 passed core, production Coinbase, strengthened T45 and unsigned device compilation; three UI cases passed. Diagnostic hierarchy showed the journal text saved while the image/export branch was absent. The screenshot case now activates the actual switch control, asserts its value and the draft preview, and still requires the saved PNG/export control. No failed run publishes an IPA. Historical contract multipliers are not fully archived, so the UI withholds unsupported contract turnover totals and the export policy states the limitation.
