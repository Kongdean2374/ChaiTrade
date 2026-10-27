# Test report

2026-10-27. Core source and evidence hashes are in TEST_EVIDENCE.json. Full 48-case status is in TEST_MATRIX.md; passing a focused core test does not establish UI/device acceptance.

- Swift 6.1.3 Linux: 40 ordinary test functions passed (one is parameterized across five provider schemas); the opt-in stress function is skipped in ordinary runs and was separately executed successfully.
- All provider quote fixtures are synthetic, including Coinbase, Fugle stocks/futures, Alpaca, Twelve Data and Binance. Credentials in fixtures are unmistakably synthetic.
- Separate Release 100,000-fill benchmark passed data count/accounting checks. Repeat measurement: save 9.57 s; full load 11.21 s; CSV 8.14 s; indexed page of 100 fills 0.00523 s. Initial save/load/CSV were 15.28/11.63/7.66 s. These are Linux measurements, not iPhone performance claims. Full-load latency exceeds the requested latency target.
- Apple Xcode 16.4 / Swift 6.1.2: core suite, two iPhone Simulator UI cases, iPhoneOS Release build, unsigned IPA packaging and artifact validation all passed on commit 3a4f3379c81e64f629a4bab90cc69f660011156b. The Swift Testing summary includes two opt-in functions skipped in the ordinary run; those are not additional executed passes.
- Simulator UI cases passed: local offline market order → TWD position (37.129 s), and onboarding/navigation → terminate/relaunch (18.690 s). See TOOLCHAIN_NOTES.md for the simulator-only WebKit deployment-target workaround. iPhone 17 Pro device acceptance remains unexecuted.

Ordinary tests cover exact arithmetic/overflow/encoding; A/B persistence and epoch; cash/fees/minimum-fee release; idempotency; shadow liquidity; cancel/amend; FOK/IOC/post-only/reduce-only; stop gaps; OCO/brackets; stale/delayed data; external cash flows and missing FX; derivative notional and deficits; margin/carry; business-day settlement; split/dividend; future basis/final expiry; deterministic paths/controls/checkpoints; encrypted and dual backups; corrupt balances; network/CSV policy; indicators; all provider quote parsers and depth gap recovery.

Logs and xcresult bundles are retained as ChaiTrade-test-evidence artifacts for each Actions run. The unsigned IPA artifact is only uploaded after required core and UI steps succeed.

Live verification: Coinbase HTTP 200; the production Swift adapter separately passed real ticker, level2 snapshot and one-minute candle reads after the test container used the session system CA bundle. Binance returned HTTP 451 from this region. See LIVE_MARKET_PROBE.json.

## Successful full GitHub run

Commit 3a4f3379c81e64f629a4bab90cc69f660011156b: [run 40451960851](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40451960851) completed successfully. Both UI tests passed. The iPhoneOS Release unsigned IPA passed resource/platform/architecture/signature checks and was uploaded with SHA-256/build-info. [Download artifact](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40451960851/artifacts/12711180423); retention expires 2026-11-03. This artifact is not device-signed or a complete 48-case acceptance declaration.

The final run includes deferred Post-only validation, stale-source handling and backup structure validation. The preceding full successful run was 40450662963 (commit c13cc51522b02c70d7d16731f71a1922c4251181).

Repository access was verified by API writes and an independent public Git clone; all 79 tracked files at c13cc515 were compared byte-for-byte with the uploaded local tree, with zero mismatches. Later source changes are recorded in the final build commit above.
