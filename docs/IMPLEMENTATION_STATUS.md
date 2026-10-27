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

## 2026-10-27 歷史投入成本與檔案快照驗證

本機完整Release **126項、零跳過**，76.314秒通過；原T45十萬成交／100001估值點、30樣本，寫入p95 **53.344567ms**、100筆分頁p95 **2.969550ms**、熱載入57.503162ms、完整CSV164.908019ms、完整稽核10.730986532秒。公開BTC/ETH三輪即時資料／兩組K線／監控恢復、官方RSS與Nasdaq身份HTTP亦通過。這些仍是Linux儲存與真實連線證據，不取代iPhone2秒冷啟動或150ms UI回饋。

新增外部資金入帳時的不可變匯率證據與歷史基準成本；匯率改變、外幣全部提回與重啟／備份後仍保留匯兌損益。缺少歷史匯率的舊資料，即使外幣淨投入為零，也明示歷史成本缺口。SQLite v6／舊v5歸檔遷移不改寫現金、帳本或原事件；備份v3拒絕被舊版誤讀，並接受v1–v3。圖表改為必要時間範圍查詢、指標化衝擊歸檔與二分時間窗口，遇到休市缺口才擴大範圍；重播及分頁測試通過。

大型封存仍在實作：目前完成一致性SQLite檔案複製、唯讀／防護模式、精確編譯結構白名單、逐列帳務查核，以及中斷複製回滾、驗證後檔案變更、觸發器／現金竄改拒絕、帶實際本機成交及歸檔資金流的原子檔案取代測試。尚未接上分塊加密／壓縮檔案格式、原生分享及還原操作，也尚未實測超512MB，不能把工具測試列為大型備份完成。舊格式32MB壓縮／512MB展開限制維持。

Apple run [40580779802](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40580779802)，commit `6c83918c8758163713d0a304a0c0bbb07a3cea8b`：裝置／UI編譯及core通過，產品7/8通過（新增百分比提醒連點建立／刪除與通知中心隔離通過），重啟後市場切換仍失敗。SE3視覺4/4通過；17Pro2/4，失敗畫面顯示大字體確認列與部分可見的數量欄位重疊、搜尋結果落在鍵盤工具列附近。產品artifact12770473582 SHA256 `1dfdaf5ac5ee9bb0b5c89c6b88115dbe39c08e5b3313c7833ddab8b849f64651`，17Pro artifact12770428794 `e32161aa53e2bb2a3e21ea911de3f5d0deb38b816c953db8c78f65ec7aff8f51` 已保存並實際檢視。修正為短而完整可點的確認列、內嵌導覽標題、搜尋時緊湊表頭、整個市場切換區可點，以及選商品收起鍵盤；等待完整重測，不增加等待門檻。

### 第十輪原互動已完整執行

run40580779802的原互動20次：17通過、2圖表日誌匯出入口失敗、1冷啟動切帳超過原120秒；整組不通過。返回／取消／滑下關閉、補算暫停與恢復、日誌連點、送單一次、自選及首輪切帳均通過。artifact12771732580（SHA256 `9ea13386c614c262a623635f5a962d2c8b3acb50b722969ef1bded6b65932a21`）已保存。日誌的原始帳戶與失敗時UI階層確認正文及圖表已保存一次，但鍵盤仍保留、下方匯出未進入可見區；原Smoke結束截圖是在完成關閉之後，不能把結束圖當成失敗時畫面。新增失敗前明確擷取診斷，不改原斷言／等待上限。

追加修正：保存後明確解除編輯焦點；B摘要工作按同一分鐘合併，避免每列出現時反覆啟動未被取消的背景工作；圖表取消會傳入實際背景計算。帳戶重綁／進背景取消舊工作，不讓舊分鐘回呼發佈新狀態。仍須重跑完整原互動與產品／視覺／逐頁證據，不能因核心通過就結案。
