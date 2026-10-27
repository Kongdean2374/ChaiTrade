# Test report

2026-10-27. Core source and evidence hashes are in TEST_EVIDENCE.json. Full 48-case status is in TEST_MATRIX.md; passing a focused core test does not establish UI/device acceptance.

- Swift 6.1.3 Linux: 37 ordinary test functions passed (one is parameterized across five provider schemas); the opt-in stress function is skipped in ordinary runs and was separately executed successfully.
- All provider quote fixtures are synthetic, including Coinbase, Fugle stocks/futures, Alpaca, Twelve Data and Binance. Credentials in fixtures are unmistakably synthetic.
- Separate Release 100,000-fill benchmark passed data count/accounting checks. Repeat measurement: save 9.57 s; full load 11.21 s; CSV 8.14 s; indexed page of 100 fills 0.00523 s. Initial save/load/CSV were 15.28/11.63/7.66 s. These are Linux measurements, not iPhone performance claims. Full-load latency remains below the requested quality target.
- Apple Xcode 16.4 core suites have passed on GitHub in preceding runs. Simulator compilation passed. UI launch smoke failed on commit 6ec0630d33b1835339f4568faf7066c420e06acc because the app did not stay running; execution settings and diagnostic collection are being corrected.
- iPhoneOS Release build, unsigned IPA packaging and artifact validation passed on commit 51ecfc9edfc3effd43b12ac89a2513958fadd013. UI launch is affected by the documented Xcode simulator WebKit issue; see TOOLCHAIN_NOTES.md. iPhone 17 Pro device acceptance remains unexecuted.

Ordinary tests cover exact arithmetic/overflow/encoding; A/B persistence and epoch; cash/fees/minimum-fee release; idempotency; shadow liquidity; cancel/amend; FOK/IOC/post-only/reduce-only; stop gaps; OCO/brackets; stale/delayed data; external cash flows and missing FX; derivative notional and deficits; margin/carry; business-day settlement; split/dividend; future basis/final expiry; deterministic paths/controls/checkpoints; encrypted and dual backups; corrupt balances; network/CSV policy; indicators; all provider quote parsers and depth gap recovery.

Logs and xcresult bundles are retained as ChaiTrade-test-evidence artifacts for each Actions run. The unsigned IPA artifact is only uploaded after required core and UI steps succeed.

Live verification: Coinbase HTTP 200; the production Swift adapter separately passed real ticker, level2 snapshot and one-minute candle reads after the test container used the session system CA bundle. Binance returned HTTP 451 from this region. See LIVE_MARKET_PROBE.json.
