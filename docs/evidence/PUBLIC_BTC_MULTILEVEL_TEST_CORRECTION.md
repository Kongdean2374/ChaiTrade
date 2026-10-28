# Actual public BTC execution audit: preserve one order across several book levels

The first real-public A-mode UI trading case failed on source `879270619a583ada495bd897637c34d4938971c7`, run [40765724515](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40765724515), job `123094943496`. Preserve that failure; it is not a passed test. The product suite recorded 17 passes and one failure, all within the unchanged 120-second case allowance.

The original screenshot and synthetic A-account SQLite database show one BTC-USD market-buy intent for 0.001 BTC, filled across three actual public book price levels. The quantities are 0.00000085, 0.00001231 and 0.00098684 BTC; their exact sum is 0.001 BTC. All three execution IDs belong to the same intent. The sum of notional, fees and taxes is 81.3641871031 USD; the cash ledger debits exactly that amount, leaving 999918.6358128969 USD from a virtual 1000000 USD starting balance. The visible receipt says fully filled, 0.001/0.001 BTC and fees of 0.08128291 USD.

The test had incorrectly required exactly one fill row for one market order. The correction checks a single exact intent and requested quantity, nonempty unique execution IDs, each execution's intent/product/non-estimated price, exact aggregate quantity, per-execution ledger reconciliation, aggregate cash and position, and unchanged execution debits after restart. It does not alter matching, accounting, App behavior, fixtures, case deadlines or the existing deterministic one-fill duplicate-submission tests. The App remains version 1.2.20 build 23 because this is a test-only correction.

Retained original failure artifact: `12852986106`, SHA-256 `a188a8b8db64d0a3e0e0b290492e4e42988cdff6b584022478b0941fa3554ba6`. The raw failure, screenshot and database remain in the original CI artifact and local evidence archive. The failure snapshot was inspected before changing the assertion. No real exchange order or funds transfer occurred; execution and virtual money remain local.

The correction requires a fresh complete same-source CI run and screenshot review. It does not make the failed run pass and does not authorize an IPA before the remaining gates pass.
