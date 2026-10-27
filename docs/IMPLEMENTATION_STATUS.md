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
| R08 native UI and charts | Features/, ChartView, ChartWeb | Implemented; Latest native compilation and nine UI cases x2 plus focused order x2 passed (40517887202); complete device/UI acceptance remains separate |
| R09 public repository | Kongdean2374/ChaiTrade | Public read/write and independent clone/download verified |
| R10 unsigned IPA | workflows/, scripts/ | Workflow and artifact validators implemented; Latest unsigned IPA produced by successful run 40517887202; user signing/device verification still required |
| R11 no actual assets | NetworkPolicy | Only allowlisted market-data GET requests; policy tests passed |
| R12 maintenance and verification | CoreTests, backups, docs, scripts | 69 ordinary core functions; Release T45 includes analytics, concurrent consistent backup, full CSV equality and backup restore. Local full Release and Apple required gates passed (40517887202); complete device acceptance pending |

Technical choice: native SQLite C bindings keep persistence identical on Linux and iOS. WAL, atomic financial transactions, migration rollback/retry and bounded indexed history are tested. This is not a waiver of full plan acceptance.

This iteration implements:

- Database schema 4: complete immutable fill/order/ledger/equity history, bounded hot state, indexed paging/search, exact CSV cache, atomic performance checkpoints, independent consistent backup reads and guarded restore/reset.
- Exact calendar week/month bars and optimized deterministic OHLC; backwards provider history paging; stock history across market closures; bounded chart caches and account/instrument preferences.
- Watermarked local chart PNGs, journal associations and export; native local notifications with stable event identities and outbox acknowledgement.
- Day/week/month fill-cycle reports, partial/flip cost allocation, NAV/drawdown prefix state and equity history paging. The UI/policy disclose the cash-flow and historical multiplier gaps in REMAINING_WORK.md.
- B fixed-clock signed long/short carry, timezone-aware daily/final settlement, stable event replay and canonical set encoding. New state schema 2; older worlds retain their saved rules. Isolated fee handling and cross-currency collateral accounting corrected.

Latest local full Release: all 71 tests executed and passed with CHAI_STRESS=1 and CHAI_LIVE=1, zero skipped. Apple run 40517887202 passed core/live, unchanged required T45, unsigned device compilation and all 20 isolated UI executions. Source, IPA and evidence are in TEST_REPORT.md / TEST_EVIDENCE.json.

[REMAINING_WORK.md](REMAINING_WORK.md) lists the incomplete product behaviors and unavailable external checks. The plan's 2 s normal B cold launch and other physical-device performance targets remain unverified.

Interaction fixes: stable journal draft identity / synchronous save guard, fixed request identity / submit guard, atomic engine favorites, catchup mutation blocking with usable sheet dismissal, fixed pause/resume locations, and order tab change after sheet dismissal. All adversarial assertions and test allowances remain; historical failed runs are retained in INTERACTION_VALIDATION.md. Older iOS18.x two-round interaction and signed-device acceptance remain unverified.


## Product completion development — 2026-10-27 (not final acceptance)

The complete original plan remains authoritative. Product work is on `product-experience-20261027`; the main-branch IPA described above predates this redesign. The current native app separates market browsing from cold A/B account switching, offers rich real-name identities, market home/list/news, chart-first details and market-specific order language, compact portfolio summaries, settings groups and data tools. Local order/accounting paths remain in TradingEngine and SQLite transactions.

Core additions include independent hedge positions, progressive risk tiers, collateral ratios, liquidation estimates and explicit estimated liquidation fills; immutable financial-flow history and full economic cycles with fixed fill multipliers/notional; deterministic offline news/events/corporate actions; distinct participant refill pools and archived own-trade impact replay; bounded visible quote requests and typed source status; official public US listing metadata search. Additive identity migration retains old holdings/history and old A trading rules until explicit flat upgrade.

Evidence: full Release100 passed with live and stress enabled, zero skipped, in `.reports/product-full-release-sixth.log`. Original T45 writep95=51.769125ms, 100,000 fills and100,001 equity points, unchanged thresholds. Real HTTP BTC/ETH quotes/stats/history/recovery, official RSS and official US directory passed. This is Linux storage evidence, not signed iPhone startup or feedback performance. Minor later corrections require a final full rerun.

Apple run40559942622 passed native device/simulator and core/T45. New product UI: stock→order→holding→journal, fresh A missing-key + multiple public quotes, and settings/bottom reachability passed; landscape selector, crypto news navigation/keyboard and post-restart market switch failed. Failure artifact12762820764 has SHA256 f127115bb836dc2c5ac9eaaba567c630c84647dde95da1056173ca69f293a716; screenshots and independent databases were inspected before fixes. Old crypto query ETH remained in SQLite; UI navigation must be verified separately. Original20 interaction executions completed:19passed and1failed on swipe-dismiss after keyboard input. The suite remains failed; all allowances and assertions are retained for full rerun.

Remaining feasible implementation includes complete calendar/session/source-unit rules, FX validity, percentage and pre-liquidation alerts/deep links, streaming archives beyond existing safe limits, visual matrix and complete original/new interaction acceptance, plus the final walkthrough, screenshots, documentation and unsigned IPA. Credentials, regional restrictions and physical-device measurements remain explicit external blockers; they do not excuse the feasible code work.

## 2026-10-27 產品補完：第九輪實測與下一輪修正

Apple run [40573828820](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40573828820)，commit `46ddeb98d4523c8b26f8d854ee9bd198d7bf6545`：裝置 Release／UI 編譯及核心通過。產品流程6/7通過（股票完整旅程、加密買賣精確帳務、公開BTC/ETH首次列表、橫向圖表、快速市場切換及重啟、七類設定與到底）；加密搜尋鍵盤後切總覽失敗。原互動共20次執行17次通過、3次失敗（鍵盤後確認鈕兩次、補算35秒內未完成一次），整組不通過。視覺 iPhone17Pro 3/4、SE3 2/4；大字體鍵盤確認與SE長中文日誌失敗。未提高120秒單例、35秒補算等待、2秒正常冷啟動或150毫秒門檻。

失敗的xcresult、畫面、階層及各例UUID資料庫均先保存並實際檢視：產品artifact12767747172，SHA256 `6195189fc61d6ac1e63eb1bd48b0430f71edb99dc155515aee1d71b72b7e63ae`；SE artifact12767642049，`4d39364d9d90f8956af322229c71dff2f04260984f4827342a3279ab16639d55`；17Pro artifact12768150208，`c55337a8e6e5d981bc7d86022ad3e4b90cf5f1a4bb4a77e57ebef30e6142ff24`；原互動artifact12768756441，`8393f42d64eff015e9f693f0b3b22ddb5b7d4e640cb70606e754498750182f78`。這些是乾淨合成測試帳戶，不含使用者原圖的私人通知。

本次修正：確認委託／保存日誌改為鍵盤上方固定操作；搜尋分類切換收起鍵盤並提供明確完成搜尋；新聞分類與自選篩選按市場獨立，返回新聞詳情不重設；大字體測試另核對sheet實際字級。圖表加上市場時區、中文時間、深淺底色、字級、量軸及固定模擬標記。補算效能修正不跳過五秒財務事件，未結／條件單和持倉仍取得完整盤，所有已提交檢查點保留完整所需盤；新增一般推進與補算全帳戶結果比對。

核心新增：具固定基準的百分比提醒、持久化保證金警示及恢復遲滯、帳戶／原事件核對通知導覽；不因通知自動切A/B。新增TWSE2026交易與交割假日、NYSE2025–27提前收盤、TAIFEX跨日與合約來源別名、CME／參考FX一般跨日時段，日曆適用年度及未核對例外保留明示。來源試撮／暫停／收盤、交叉買賣盤與股票張股量能分開處理；同序號狀態惡化不可忽略。付費Fugle等仍只有schema合成驗證，沒有合法Key不宣稱實連。

本機完整Release117項、零跳過，70.470秒通過；原T45十萬成交／100001估值點、30樣本，寫入p95 **46.545907ms**，100筆分頁p95 **2.799130ms**，熱載入66.681274ms，完整CSV148.520757ms、完整稽核10.142075155秒。真實公開BTC/ETH三輪行情、K線、時間戳、監控恢復、本機冪等意圖、官方RSS與Nasdaq身份HTTP通過。此為Linux儲存／連線證據，不是iPhone2秒冷啟動或150ms UI回饋。後續補算優化另有核心重跑；最新版Apple UI與最終IPA尚待本輪完整重跑。
