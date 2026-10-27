# Test report

2026-10-27: Swift 6.1.3 official Linux image with SQLite and OpenSSL development headers. `swift test`: **23 tests passed**, 0 failures, approximately 0.5 seconds test execution (excluding compilation). Tests are in `Packages/ChaiTradeCore/Tests/ChaiTradeCoreTests/CoreTests.swift`.

Covered: decimal arithmetic/overflow/encoding, isolation/persistence, plan vectors A/B, minimum fees on partial fills, idempotency and epoch, shared liquidity, reservations/cancel/amend, FOK/IOC/post-only, stop-limit gaps, OCO/bracket, stale/delayed data, external cash flows, missing FX, derivative valuation/liquidation deficit, deterministic market paths/checkpoints, authenticated backup/wrong password/tampering, corrupt ledger rejection, pending mode, network whitelist, CSV injection, selected indicator vectors, Coinbase fixture parser.

Not executed at this point: Xcode device build, XCUITest, iPhone 17 Pro device verification, complete 48-case acceptance and 100,000-fill stress measurement. Build/test logs will be published as Actions artifacts when the workflow runs. A passing core suite is not a claim of complete product acceptance.
