# Retained App 1.2.20 (23) failures and diagnosis

These are original failures, not passes. Neither a later successful run nor a test correction changes their verdict. Main and the unsigned IPA remain blocked until the current source passes its full checks and product review.

Source `879270619a583ada495bd897637c34d4938971c7` ran all 77 UI executions: 76 passed and one failed. All were within 120 seconds and all 77 sessions had independent A/B account directories. The new public BTC test incorrectly required one execution row for one market order; the retained screenshot and exact ledger showed one intent spanning three public book levels. See [the original failure and test correction](PUBLIC_BTC_MULTILEVEL_TEST_CORRECTION.md). The original deterministic one-fill duplicate-confirmation tests all passed and are retained.

Source `fb19f937eb791303d30a6081feefd95ee308096e` changes only that test and its explanation. Its two 184-function normal Core suites passed, including five required actual-public-HTTP success markers. Its T45 results diverged:

| Run / job | Original 30-sample write p95 | Result |
|---|---:|---|
| 40772532323 / 123113229667 | 92.623718 ms | Passed this T45 run; full archive also passed |
| 40772532303 / 123113229711 | 174.810185 ms | Failed the unchanged 150 ms threshold; archive step did not run |

Both use 100000 original fills, 100001 equity points, the complete hot projection and concurrent full-history snapshot. The failure artifact is `12853417297`, SHA-256 `ea01397562dfd167bacd2433968cedb4aca7bf3d08ef03b551f4b0d6ccfc1c8d`. The successful archive is 576956203 encrypted bytes / 768293088 JSON bytes, with 320 original attachments and journals. A successful group does not cancel the other group's failure. Mac storage metrics do not establish physical iPhone cold-launch or UI-feedback performance.

Same-source diagnosis run [40774351846](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40774351846) enables only the existing `CHAI_STORAGE_PROFILE` compile flag. It measures the original 30 writes and original assertion; it is diagnosis, not acceptance. No FULL-sync setting, original history window, exact count, immutable payload check or rollback requirement is removed.

The same source's Pro visual group recorded five passes and one failure. `testDarkLargeTextOrderKeyboardCancelHasNoSideEffects` failed after 86.560 seconds because `orderQuantity` never became fully visible. Its original screenshot was viewed before editing the helper. All seven drags began at `(341.7,683)` inside the price input rectangle `(32,656.7,338,49.7)`, leaving the quantity at `(32,914.7,338,49.7)`. The preceding source had the same initial geometry and two unsuccessful drags before scrolling. The correction under test moves the pan to the blank right gutter; complete-target visibility, live hit testing, seven-gesture maximum, 120-second deadline and exact cancel/accounting assertions remain required. This is still a failed case until the corrected path is actually rerun; it is not yet established that the App itself cannot scroll.

Pro failure artifact `12854556436`, SHA-256 `2b2a6f0c5b206d294ab2595cb83b5bd4d34d9c31c9f82b42b48d521009af1bde`; its 12 independent account databases passed read-only integrity checks. Original PNG, accessibility hierarchy, geometry logs, SQLite files and complete ZIP remain retained. No private phone screenshot is published.
