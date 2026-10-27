# Real market data

| Source | Implemented paths | Capability / verification |
|---|---|---|
| Coinbase Exchange | product catalog, ticker, level2 REST book, candles; public level2/ticker/heartbeat WS | E1 snapshot/stream; synthetic parser and depth tests; live outcome in probe artifact |
| Fugle stocks | catalog, intraday quote/candles | Entitlement required; synthetic fixture passed; live user credentials not available |
| Fugle futures | real contract catalog, intraday quote/candles | Contract identifiers preserved; multiplier/expiry confirmation required; synthetic fixture passed |
| Alpaca | market-data IEX snapshot/bars | E2, IEX only; no broker asset/account endpoints; synthetic fixture passed |
| Twelve Data | forex catalog, reference quote/time_series | E3 reference only; volume unknown stays missing; synthetic fixture passed |
| Binance public USD-M | exchangeInfo, depth, premiumIndex, last ticker, klines | Trade price, index and mark kept distinct; synthetic fixture passed |

A defaults to immediate execution only with valid realtime data and E1/E2. E3 needs explicit opt-in and is permanently marked as estimated. A derivative missing a source mark must either pause or use the separately enabled custom reference-risk model, labelled as such.

Credentials are user supplied in Settings and stored in `WhenUnlockedThisDeviceOnly` Keychain. B never reads them. Authentication, permission, rate-limit, redirect, source maintenance and network errors have separate messages; raw credential-bearing URLs/responses are not logged.

Coinbase WS uses its ordered level2 snapshot/change semantics, not an incorrectly assumed full-channel sequence. Every new connection requires a new snapshot; dropped local buffers disconnect and rebuild, with exponential jittered retries. A separate tracker tests contiguous and Binance previous-update policies. Other providers currently use REST snapshots; complete per-provider WebSocket lifecycle and source failover remain unaccepted.

The initial default-client probe received HTTP 403; the app User-Agent probe later returned HTTP 200. The production Swift adapter also passed live ticker/book/candle reads. Binance returned HTTP 451. `scripts/probe_public_market.py` records actual GitHub runner success/failure without retaining market values or blocking credential-free builds. Source availability and user entitlements are external conditions; no live-success claim is made from fixtures.
