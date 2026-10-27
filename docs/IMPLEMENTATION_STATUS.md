# Implementation status

Date: 2026-10-27. Work is in progress against the entire REQUIREMENTS.md; this is not a completed acceptance declaration.

| Area | Source / evidence | Current state |
|---|---|---|
| R01 A real market data / local trading | MarketData.swift, TradingEngine.swift | REST adapters implemented; credentialed live verification blocked by missing user entitlements |
| R02 B offline market | Simulation.swift, ChartWeb | 120 tradable + 5 indices; deterministic paths, five-second events; core tests passed |
| R03 A/B isolation | Persistence.swift, AccountContext, CoreTests | Separate database files and epoch validation tested |
| R04 cold-launch switching | AppModel.boot, AppSettings | Implemented; pending-state unit test and terminate/relaunch UI smoke passed; full A/B switch acceptance pending |
| R05 funding | cashFlow/exchange, CashView | Exact values, cash reservations, external-flow separation tested |
| R06 full scope | REQUIREMENTS.md and this table | Not yet fully accepted; missing behaviors tracked in KNOWN_LIMITATIONS |
| R07 order types and markets | TradingEngine, RulePack, OrderForm | Market/limit/stop/trailing/OCO/bracket, FOK/IOC/post/reduce; core tests passed for covered cases |
| R08 native UI and charts | Features/, ChartView, ChartWeb | Implemented; Latest native compilation and all four UI cases passed (40481713600); complete device/UI acceptance remains separate |
| R09 public repository | Kongdean2374/ChaiTrade | Public read/write and independent clone/download verified |
| R10 unsigned IPA | workflows/, scripts/ | Workflow and artifact validators implemented; Latest unsigned IPA produced by successful run 40481713600; user signing/device verification still required |
| R11 no actual assets | NetworkPolicy | Only allowlisted market-data GET requests; policy tests passed |
| R12 maintenance and verification | CoreTests, backups, docs, scripts | 65 ordinary core functions; Release T45 includes analytics, concurrent consistent backup, full CSV equality and backup restore. Local full Release and Apple required gates passed (40481713600); complete device acceptance pending |

Technical choice: native SQLite C bindings keep persistence identical on Linux and iOS. WAL, atomic financial transactions, migration rollback/retry and bounded indexed history are tested. This is not a waiver of full plan acceptance.

This iteration implements:

- Database schema 4: complete immutable fill/order/ledger/equity history, bounded hot state, indexed paging/search, exact CSV cache, atomic performance checkpoints, independent consistent backup reads and guarded restore/reset.
- Exact calendar week/month bars and optimized deterministic OHLC; backwards provider history paging; stock history across market closures; bounded chart caches and account/instrument preferences.
- Watermarked local chart PNGs, journal associations and export; native local notifications with stable event identities and outbox acknowledgement.
- Day/week/month fill-cycle reports, partial/flip cost allocation, NAV/drawdown prefix state and equity history paging. The UI/policy disclose the cash-flow and historical multiplier gaps in REMAINING_WORK.md.
- B fixed-clock signed long/short carry, timezone-aware daily/final settlement, stable event replay and canonical set encoding. New state schema 2; older worlds retain their saved rules. Isolated fee handling and cross-currency collateral accounting corrected.

Latest local full Release: all 67 tests executed and passed with CHAI_STRESS=1 and CHAI_LIVE=1, zero skipped. Apple run 40481713600 passed core, required strengthened T45, device compilation and all four UI cases. Latest source/IPA links and actual timings are in TEST_REPORT.md and TEST_EVIDENCE.json.

[REMAINING_WORK.md](REMAINING_WORK.md) lists the incomplete product behaviors and unavailable external checks. The plan's 2 s normal B cold launch and other physical-device performance targets remain unverified.

互動專項新增五項對抗性案例及逐案例獨立資料，首次 Apple 執行尚未完成；詳見 INTERACTION_VALIDATION.md。既有四項正常流程證據不涵蓋本輪新增驗證。

互動基準 run 40488978661 已完成：9 個獨立案例中 3 個失敗，證據先行保留；確認日誌五筆（四筆空白）及補算面板被整體停用，自選另有手勢送達數假設問題。修正後本地 70 項完整 Release 通過、零跳過；Apple 九案例各兩次重跑尚未完成。詳見 INTERACTION_VALIDATION.md 與 INTERACTION_BASELINE.json。

修正版 run 40493670109 的核心、T45 與裝置版建置通過，但 UI 測試程式在 InteractionTests.swift:8 發生 optional／比較式型別推斷錯誤，未執行案例。證據 artifact 12730597113 保留；改成明確的 [String:Any] 與 Int 後重跑，沒有修改 >0 條件或其他門檻。補算案例另增加完成後圖表時間與最後模擬分鐘一致的驗證。

兩輪互動 run 40495754856 已完整執行 18 次、18 個獨立目錄及 36 份帳戶資料庫，15 次通過、3 次失敗，證據 artifact 12732197033（SHA-256 已核對）。日誌、自選、返回／鍵盤及既有正常流程兩次均通過。錄影重現連點繼續會命中新換上的暫停按鈕；改成兩個固定位置的常駐控制項，保持停用而不置換位置，並新增切換前後 frame 相同的斷言。下單另先等待可見的「送出中…」再檢查不可關閉，修正測試早於 Task 呈現的時序；扣款／筆數條件及 35 秒補算完成上限均不變。新一輪完整兩次 UI 重跑待完成，詳見 INTERACTION_RETEST.json。
