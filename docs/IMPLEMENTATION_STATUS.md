# Implementation status

## 目前：1.2.5（8）已提交，核心及原生編譯通過，UI 驗收進行中

來源 `345d4cb15edf2abf696e048f215ddd709e03f0fb`；[新流程 CI](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40635943352)、[完整產品 CI](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40635943331)。177 項核心、真實公開 BTC／ETH 持續行情／K 線與本機冪等委託、原 T45、大型加密封存，以及 Apple 裝置／模擬器編譯通過。15 新流程、20 原互動、17 產品、5 頁面及雙尺寸各6視覺，共69次UI仍須全部實跑。

1.2.4 的完整換 ETH 一次成交已通過，但整體失敗；已保留並實看後修正快速搜尋字元遺失、清除畫面與模型不同步、大字體鍵盤工具列重疊。picker 動畫後才核對精確身份；證據擷取重用同一份 AX 階層，不刪任何帳務斷言或提高120秒。保留原安全帳務、A／B隔離、資料及所有功能。沒有產出新版 IPA或重設使用者帳戶。詳見 [目前驗證紀錄](VALIDATION_CURRENT.md)；以下為歷史批次，不能轉算本提交通過。

## 歷史：1.2.4（7）修正原生編譯，完整回歸待做

1.2.3被Swift型別推導錯誤阻擋，未執行的UI不計通過。已拆分草稿提示字串，全部14個新流程與原完整回歸將在1.2.4同提交重跑；無新IPA、不放寬門檻。以下為前輪紀錄。


## 歷史：1.2.3（6）完整原生驗證待完成

目前核心177項本地通過，前一版新UI10／11通過仍不算完成。實際失敗已保留再修：ETH鍵盤工具列／搜尋排序、委託選單整列點擊、下滑關閉、內嵌圖表捲動；平倉方向是AX定位錯誤，已改固定識別與精確值，最終帳務斷言保留。最新版14個新流程、原20次及所有產品／頁面／視覺／核心／T45須同提交完整重跑，無新IPA。見 [TEST_REPORT.md](TEST_REPORT.md) 及 [NAVIGATION_FLOW_VALIDATION.md](NAVIGATION_FLOW_VALIDATION.md)；以下是先前批次紀錄。


## 歷史：1.2.2（5）尚待完整實跑（2026-10-28）

前一輪新流程UI 5／8通過，3例失敗，不能結案。已保存並實看失敗證據，針對picker鍵盤、草稿衝突呈現與跨市場新聞／訂閱補修；新增11例新流程，原核心、互動、產品與視覺回歸保留。以 [NAVIGATION_FLOW_VALIDATION.md](NAVIGATION_FLOW_VALIDATION.md) 與 [TEST_REPORT.md](TEST_REPORT.md) 最新證據為準，以下為先前批次紀錄。沒有新IPA，沒有重置帳戶或降低驗收門檻。


## 2026-10-28 最新操作流程補完進行中

已提交 1.2.0（3）／a12d865：行情內導覽詳情、明確買賣帶入交易、交易獨立選擇器、按帳戶保留草稿與衝突處理、一般／零股共用行情排程、手動刷新去重及來源退避。原資料未重置，工作流先測試，不自動打包 IPA。174 項 macOS 核心、T45、裝置／模擬器編譯及大型備份關卡通過；UI 尚待完成。下一本地修正 1.2.1（4）尚未提交／驗證，不算完成。具體 NF01–NF09 及證據見 [NAVIGATION_FLOW_VALIDATION.md](NAVIGATION_FLOW_VALIDATION.md)。


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


## 2026-10-27 23:36 進行中的整合狀態

工作環境已恢復；最新詳細證據與尚未完成項目見 [產品驗證紀錄](PRODUCT_VALIDATION_20261027_LATEST.md)。日誌／附件新增SQLite v7索引分頁、按需完整讀取、v6增量遷移與備份保全；本機快速核心156項通過（不是付費來源或實機驗收），超512MB量測及Apple完整回歸持續進行。正式A新聞新增TWSE／CryptoSlate，已核對來源個人RSS條款，原生整合及新增實連案例待本輪驗證。未改原T45、150ms或2秒門檻。

2026-10-28：商品目錄由資訊說明頁補為可直接搜尋、分類、分頁與選商品的實際入口；A來源探索移獨立頁且保留動態查核。合約新增風險啟用與取消、拒單在面板內保留輸入；舊格式備份增加一致性容量下限預檢，還原前使用檔案恢復點。Coinbase獨立端點並行但維持共用配額與原新鮮度限制。核心161項快速通過；最新Apple記憶體、完整產品／互動回歸仍在進行，不宣告完整產品完成。


## 2026-10-28 完整匯出查核與分享暫存隔離

先新增獨立資料反例，重現匯出只查熱資料而漏掉已歸檔日誌，以及同長度檔案變更仍產出封存，保留 `.reports/product-export-verification-red.log`。修正後在整理快照後逐列查核完整原始帳務／附件，完成串流時再次比對已查核檔案的SHA256；失敗不留下完成檔或partial，也不修改原帳戶。測試注入曾重複翻轉同一byte，已改為鎖保護的單次注入；該次失敗紀錄一併保留。

新增AccountShareCache，只列目前帳戶有UUID身份的完成檔，排除partial、未知檔案、目錄及symbolic link；清除不碰另一帳戶、帳戶資料或恢復點。原生頁面可重啟後重新分享完成檔，提供日期／大小／多檔選擇；新增重啟後分享的UI斷言，未刪舊斷言。

本機快速核心165項通過（28.225秒），真實來源與T45環境開關在這次快速回歸未啟用，不能當完整實連／規模通過。完整Swift語法及本機圖表腳本通過，不代表Apple型別檢查。後續Apple／完整Release／大檔仍須重跑。

37a7a82的Apple產品工作40609716534目前native、core、17Pro與SE3視覺各4/4、逐頁證據4/4通過；產品旅程與原互動仍執行中。逐頁artifact12783162238已完整下載並核對SHA256 `61356081bff0dcb6e57c022b6cbc7ede7914f551fca20fabcea8a6c31fa591e0`，已實際檢視商品目錄、設定七分類、帳戶、交易偏好、離線模擬、績效、資料工具、資金與自選分組等畫面。不是只讀檔名。尚未列成最終走查或完成交付。


## 2026-10-28 生命週期SQLite v9與產品反例

新增交割／持有費／股務的原始歷史索引及每類100筆熱投影，所有待交割義務全部保留。完整備份／封存還原全紀錄，拒絕以熱投影取代完整帳戶；已歸檔內容不可覆寫，交割僅允許原金額／到期日不變的待交割→完成。明確版本9安全遷移並接受原6–8檔案封存；新增分頁中文歷史頁（每頁20筆、單頁記憶體、帳戶／回呼核對）。

獨立合成帳戶實際成交後產生240次配息，驗證240筆待交割不被裁掉、完成後仍有完整240筆、原ID重送／重啟／完整備份還原不會重派，分頁無漏無重。另有v8全歷史遷移、注入中斷回滾、舊版封存驗證、原始列序號竄改、已完成交割回退及持有費變更拒絕。首次回歸抓到舊金融流重建只讀熱持有費，已改取完整歸檔後重建，失敗紀錄保留。核心167項31.245秒通過；後續完整Release／Apple／大檔量測仍待重跑。

37a7a82產品15例為13通過、2失敗（合約風險取消後重開保留勾選、目錄／背景相同識別導致多重匹配），整組不通過。ZIP artifact12784100806 SHA256 `0c16c80f39e2d6ebfab5da3e42fb36c72810a76f11f4b3ba120a3d04a3a7871e` 已先下載保留；實際檢視風險失敗PNG與目錄錄影擷取畫面，再修正風險確認每次開啟重設、目錄專用識別，並新增重開未勾選／啟用按鈕狀態斷言。不增加120秒門檻。

d1fb385的Apple原生及獨立大檔量測通過；core發現macOS暫存路徑 /var 與 /private/var 的URL文字比較問題。分享工具改保留呼叫端路徑，仍以完整解析路徑核對暫存目錄、拒絕分享目錄跳轉；測試比較實際檔案身份，未取消跨帳戶及symbolic-link保護。該次失敗日誌已保留；須在Apple重新測試。

上一個完整Release（新增v9之前）165項69.113秒、零跳過通過；原T45寫入p95 42.385537ms、100筆查詢p95 2.479824ms、熱載入47.804021ms、十萬筆CSV122.936277ms。實際公開BTC/ETH多輪、兩組K線、斷線標記恢復、本機一次成交、Fed／TWSE／CryptoSlate及Nasdaq目錄實連通過。此為Linux儲存／實連證據，不替代實體iPhone原2秒或150ms UI回饋。


## 2026-10-28 成交流程與實際圖表繪製

37a7a82原互動工作122559501827已完整20次通過（2次下單焦點＋原9例各2次），沒有跳過後續案例。產品仍13/15，不能以原互動綠燈取代產品失敗。最新v9完整Release167項、零跳過74.320秒通過；原T45寫入p95 44.936728ms、100筆分頁2.770272ms、熱載入73.402704ms、十萬筆CSV149.960096ms，完整公開BTC/ETH等實連通過。1a41299診斷40613990548的Apple原生、核心、原T45與大檔均通過；已保持fast-forward推進產品分支作完整回歸及IPA。

實際檢視股票→委託→資產→日誌及加密新聞／橫向圖表影像，發現瞬間成交後預設未完成列表的大型空卡會遮住成交回報。新增按帳戶epoch綁定的本次回報：名稱代碼、方向、委託狀態、成交／原數量、手續費及此委託保留，明示成交稅及交割另列；不新增第二組撤改按鈕，也不更動金融事件。取消、拒絕與瀏覽不能產生成功回報，還原重綁會清除舊epoch回報。

橫向實圖確認K線／均線／量能／時區已繪製；初進商品圖曾在WK完成前拍到空白。加上本機繪圖載入提示與失敗說明，兩個animation frame後核對可見canvas及真實K線數，依商品／帳戶epoch／週期分開記錄inline與fullscreen完成狀態。截圖只允許已完成繪圖；UI測試強化實際繪圖與成交狀態斷言，不能只憑webView存在判通過。新增5例焦點回歸作補充，完整原20次及全產品／視覺仍必須執行，120秒單例不改。Apple重測進行中。


## 2026-10-28 完整JSON／CSV逐筆檔案匯出

新增AccountDataFileService，在釋放引擎維護鎖後由獨立一致性快照查核及逐筆寫檔，不先fullSnapshot或組成整包Data。完整JSON保留全部委託、成交、事件、帳本、估值、金融流、冪等身份、股務／交割／持有費、日誌原PNG，並從原始成交逐組重建B已歸檔衝擊。A排除報價／撮合快取，兩模式與epoch不混用。CSV延續原欄位、CRLF及escaping；原T45的Data API保留，原生匯出改檔案路徑。

容量超限、取消、原始歷史損壞或查核後快照變更均拒絕，不留下完成／partial檔，不覆寫原檔或帳戶。資料分享暫存按帳戶及檔案種類分開，可重啟後重新分享；清除JSON／CSV不動可還原封存。新增獨立A／B實際本機帳務路徑，含120筆日誌、7張PNG、120次配息、歸檔衝擊，JSON解碼後與完整快照逐欄相同，三種CSV與Analytics完整輸出逐byte比對。取消、容量、損壞、既存檔案不覆寫及分享隔離反例通過。

本機快速170項35.952秒通過。最新完整Release170項74.944秒通過（大檔案例明確列為本命令未執行，另由必要獨立步驟實跑，不能將其環境關閉時早退當實測）。原T45十萬成交／100001估值點、30樣本：寫入p95 52.214804ms、100筆分頁4.806549ms、熱載入71.370309ms、完整CSV137.402697ms，真實公開BTC/ETH三輪、兩組K線、RSS與目錄實連通過。大檔步驟新增>512MB完整JSON、逐行獨立解碼320張PNG核對及記憶體量測，原128MiB增量門檻不放寬；目前仍在跑。原生分享／重啟新例與新增圖表、深度、進階委託及商品規格畫面取證須Apple重跑。


### 新串流資料格式的大檔實跑

`.reports/product-stream-data-archive-scale.log`：Linux獨立Release案例82.834秒通過，577167360-byte SQLite、576954948-byte加密封存、768293088-byte完整JSON，原320份PNG經封存還原及逐行JSON獨立解碼逐張SHA256一致；取消後原帳戶保留。基準峰值62107648、總峰值78573568、增量16465920 bytes，低於原128MiB增量門檻，未改門檻。這是Linux程序的實際大檔測試，不是Apple或iPhone記憶體證據；Apple新格式仍待跑。


## 版本遞增與1a41299返回修正

依使用者要求，本輪由原1.0.0（1）升為1.1.0（2），version.json為單一來源，專案產生器同步Debug／Release，App設定／關於顯示實際Bundle版本。CI檢查前一提交的App／核心變更是否同時升版本與建置，checkout保留兩層歷史；IPA Info.plist、build-info.json、版本檔名及SHA256須一致。新增bump_version.py供後續修正版／功能版遞增，AGENTS已記錄。文件更新不冒充新的App版本。

新增版本檢查、專案再生、資源校驗、安全格式掃描、YAML／Python／Shell檢查已在本機通過；實際IPA版本查核仍待本輪Apple建置。完整帳務返回例按實際NavigationStack逐層返回並保留原資料斷言。e79ad95最新Apple原生編譯已通過，焦點UI正在跑；不能因只編譯通過就結案。


## 2026-10-28 新增：行情詳情與交易分工（優先實作與驗收）

使用者實測修正原選商品直接跳交易的流程。此要求接續完整計劃，不取消既有功能、資料、安全帳務或測試。現在selectProduct同時設定selectedID及tab=2；瀏覽與交易共享上下文，是已確認的不符要求行為。新工作將分開行情導覽、活躍圖表焦點及交易選取／未送出草稿；只有明確買賣動作才建立精確商品身份與方向的handoff。

新增三個獨立乾淨UI反例，2330／BTC／ETH點入後必須仍選中行情、無下單面板／成交，返回保留搜尋；先在目前程式執行並留證，再改產品。另新增來源Retry-After不得被連按手動刷新清掉的核心反例。完整矩陣與進行中狀態見NAVIGATION_FLOW_VALIDATION.md。

後續測試先行，不啟動新的產品分支IPA自動建置；主分支必要關卡與未簽名流程保留。既有IPA不是新導覽驗收，不能請使用者安裝代找基本問題。
