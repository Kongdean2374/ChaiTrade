# 48 項驗收矩陣

## 目前：1.2.7（10）修正鍵盤後滑下關閉，完整70次UI待重跑

上一版a79f642的69次UI已完成：65通過、4未過（原互動19／20、產品15／17、SE5／6；新流程15／15、頁面5／5及Pro6／6通過）。失敗圖片、原生階層、錄影、診斷與140份獨立A／B資料庫已保存並核對完整性。沒有把逾時、滑下關閉失敗或未顯示的圖表改標為通過。

原互動第二次滑下關閉的實際圖A589B6D1顯示下單表單及鍵盤均留在畫面，orderDismissRequests仍為0。原本SwiftUI手勢僅掛在導覽列標題，無法穩定收到鍵盤開啟時交給UIKit導覽列／sheet的拖動。本版使用實際UINavigationBar上的原生垂直pan觀察，同時允許系統手勢、不攔截其他按鈕；向下拖動仍先取消未送出表單，保留草稿且零送單。送單中、摘要確認中與已成交後不接受取消，離頁移除觀察器。

新增獨立乾淨案例，先用原導覽列swipe，再由標題外的空白區拖動；兩次都核對鍵盤與sheet關閉、草稿保留、商品／方向／帳戶不變、零委託／成交／扣款。原20次互動及全部斷言完整保留，總數增加為70次UI（新16＋原20＋產品17＋頁面5＋兩尺寸各6）。股票旅程也保留先捲到完整可見圖表再於原10秒驗證繪製的測試操作修正。

App版本及build已同時提高，未重設任何帳戶。177核心、真實公開行情、原T45與大型封存全部仍須本提交重跑；原120秒／150ms／2秒門檻不變，沒有新版IPA。詳細外部條件與前輪證據見[目前驗證紀錄](VALIDATION_CURRENT.md)。以下為歷史批次。


## 目前：1.2.6（9）實際回歸未全過，修正圖表測試操作後完整重跑

來源 `a79f64281d04171b9ba48ebae1803601f195b2d3`：[新流程 CI](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40640699521)、[產品 CI](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40640699623)。同提交177項核心、真實公開行情／K線／RSS／目錄、原T45及超512MB完整封存通過；新流程15／15、頁面5／5、Pro6／6。產品15／17（股票圖表1失敗、合約旅程1逾時），SE5／6（首次自動化啟動68秒後總案例逾時）；原互動20次仍待結果。整組不通過，未產出新版IPA。

已先下載、核對SHA256並實看原始失敗圖片／階層／狀態／診斷。股票圖表整個在可見範圍下方，測試尚未捲動就等WebKit動畫回呼；現在先以原完整可見規則捲到圖表，再保留原10秒繪製檢查，之後捲回整股選擇器。合約的兩筆委託、唯一減倉及零部位斷言於107秒前完成，切資產後模擬器Metal編譯XPC阻塞至168秒；這不是通過。SE資產底部、設定診斷與關閉均已操作，但整個案例逾120秒仍失敗。這次只修測試定位及文件，App／Core內容和1.2.6（9）版本不變；新版全部69次原生UI、177核心及規模關卡須同一提交重新完成，不降低任何門檻。

實測數值、獨立資料庫核對、失敗證據與外部條件見 [目前驗證紀錄](VALIDATION_CURRENT.md)。以下為歷史批次，不能當作目前提交全數通過。


## 最新操作流程測試索引（2026-10-28）

1.2.6（9）改固定合約平倉入口，必須重跑同提交69次UI；保留全部舊門檻與帳務斷言。前版345d4cb合計67／69（新流程15、原互動20、產品16、頁面5、視覺11），原T45／177核心／大型封存／公開HTTP通過，整體未通過。以下為前輪索引，不自動轉算新版通過。

目前345d4cb／1.2.5（8）包含15個新流程案例，其中新增空搜尋後清除畫面與模型同步；完整UI應完成69次執行，尚待全部結果。當前177核心、原T45／大型封存／公開HTTP已實跑通過。詳見[目前驗證紀錄](VALIDATION_CURRENT.md)，以下48項不因本輪操作改版自動升為完成。

新增 `NavigationFlowTests`（2330／BTC／ETH 各自全新資料）、`TradingHandoffTests`（ETH 賣出與市場→詳情→買進→獨立換商品→一次模擬成交）、`TradeWorkspaceInteractionTests`（草稿衝突保留／放棄、分類／搜尋／清除、B 快速刷新不變時鐘與行情）。核心另測精確身份、錯帳戶／epoch、舊 autosave、保存／重啟／加密備份、舊偏好相容、429 Retry-After 與目前／可見優先。新增大小螢幕深淺色的選擇器／中文鍵盤／展開篩選案例；不取代既有核心與互動測試。實跑結論以同提交 [TEST_REPORT.md](TEST_REPORT.md) 及 [NAVIGATION_FLOW_VALIDATION.md](NAVIGATION_FLOW_VALIDATION.md) 為準；新增案例尚未全數實跑通過。


本表的「通過」僅適用明列的核心自動化案例；不是整體實機驗收。測試來源位於 Packages/ChaiTradeCore/Tests/ChaiTradeCoreTests/ 及 ChaiTradeUITests/SmokeTests.swift 及 InteractionTests.swift。UI／IPA 狀態以 Actions 實際結果更新。外部憑證測試尚無使用者權限，不捏造成功。

| ID | 計劃書案例 | 狀態 | 方法與證據 |
|---|---|---|---|
| T01 | A 花 10,000、B 尚未交易 | 通過 | vectorAAndIsolation |
| T02 | 設定待切換後繼續本次使用 | 部分通過 | run 40517887202: pending mode keeps B banner/context; complete trading acceptance pending |
| T03 | 切到背景再回前景 | 部分通過 | run 40517887202: background/activate preserves mode; complete lifecycle acceptance pending |
| T04 | 目標帳戶資料庫或遷移故障 | 未執行 | 需完整整合／UI／實機驗證 |
| T05 | 舊行情回應延遲抵達 | 通過 | duplicateRequestAndEpoch |
| T06 | 首次安裝就飛航模式啟動 B | 未執行 | 需完整整合／UI／實機驗證 |
| T07 | A 無 API Key／無權限 | 部分通過；實際受限來源外部阻擋 | 40559942622 fresh A UI驗證缺Key說明、不顯示股票下單入口、仍可看委託；401/403/429等核心分類測試。使用者合法憑證的實連仍未取得。 |
| T08 | A 僅取得延遲資料 | 未執行 | 需完整整合／UI／實機驗證 |
| T09 | 中斷報價／深度漏包 | 未執行 | 需完整整合／UI／實機驗證 |
| T10 | 背景或斷線期間價格穿過停損 | 未執行 | 需完整整合／UI／實機驗證 |
| T11 | 多次點擊送單／事件重送 | 核心及所列 UI 通過 | duplicateRequestAndEpoch; concurrentDuplicateOrderIntentDebitsOnceAcrossRestart; run 40517887202 rapid confirmation/cancel exact debit, 4 isolated executions |
| T12 | 多張委託同時保留相同資金 | 通過 | reservationsAndCancel; partialCancelAndSharedLiquidity |
| T13 | 部分成交後撤單 | 通過 | partialCancelAndSharedLiquidity |
| T14 | 分成多筆成交且有最低手續費 | 通過 | minimumFeeNotRepeatedOnPartialFills; partialFillReleasesAlreadyPaidMinimumFeeReservation |
| T15 | OCO 雙邊近乎同時觸發 | 通過 | ocoAtomicAndReduceOnly |
| T16 | 括號主單部分成交 | 通過 | bracketFollowsActualFills; bracketPartialExitRemainsProtected |
| T17 | Reduce-only 遇到部位減少 | 通過 | reducedPositionCannotReverseOnSecondExit |
| T18 | FOK／IOC／Post-only | 通過 | fokAndIOC; postOnlyAndAtomicAmend |
| T19 | 市價滑價或資金不足 | 未執行 | 需完整整合／UI／實機驗證 |
| T20 | 停損限價跳空 | 通過 | stopLimitGapDoesNotGuaranteeFill |
| T21 | 小數幣量、多次加減與捨入 | 未執行 | 需完整整合／UI／實機驗證 |
| T22 | 超大本金、非法精度或乘法溢位 | 通過 | exactDecimalAndSerialization |
| T23 | 缺少匯率／估值價格 | 通過 | moneyFlowIsNotProfitAndFXIsIncomplete |
| T24 | 人工入金／減資 | 通過 | moneyFlowIsNotProfitAndFXIsIncomplete |
| T25 | 逐倉／全倉與調整保證金 | 未執行 | 需完整整合／UI／實機驗證 |
| T26 | 資金費率、借貸利息重啟重播 | B 核心通過；A 未實測 | offlineFundingScheduleIsExactSignedAndReplaySafe; fundingReplayAndMarginAdjustment; source entitlements pending |
| T27 | 強平與穿倉 | 通過 | derivativeNotionalIsNotAnAssetAndLiquidationKeepsDeficit |
| T28 | 每日／到期結算 | 核心通過 | futureSettlementResetsBasisAndExpires; offlineDailyAndFinalSettlementAreAtomicAcrossRestart; missing-DST-time schedule |
| T29 | 分割／反向分割／股息 | 通過 | splitVectorDAndDividendIdempotency; corporateSplitDoesNotRewriteOfflineHistory |
| T30 | 日光節約時間、休市與零股盤 | 未執行 | 需完整整合／UI／實機驗證 |
| T31 | B 固定種子連續執行與多次重啟 | 通過 | offlineRejectsNetworkAndReplayCheckpoint |
| T32 | B 多看圖／改週期／增載歷史 | 通過 | deterministicCatalogAndTimePaths |
| T33 | B 當前 K 線 | 通過 | deterministicCatalogAndTimePaths |
| T34 | B 1× 與 100× 推到同一模擬時間 | 未執行 | 需完整整合／UI／實機驗證 |
| T35 | B 離開補算到一半被終止 | 未執行 | 需完整整合／UI／實機驗證 |
| T36 | B 切到 A 一段時間後再切回 | 未執行 | 需完整整合／UI／實機驗證 |
| T37 | 調整手機時間與時區 | 未執行 | 需完整整合／UI／實機驗證 |
| T38 | A／B 備份還原與完整重設 | 未執行 | dualAccountBackupAndCSVNumbers |
| T39 | 壞備份、錯密碼、錯模式、路徑穿越 | 通過 | backupRoundTripEncryptionTamperingAndWrongMode |
| T40 | schema 遷移被中斷 | 核心通過 | injected failures/retries for schema 1, 2 and 3; physical termination acceptance pending |
| T41 | 指數商品與資料缺失功能 | 未執行 | 需完整整合／UI／實機驗證 |
| T42 | E3 參考價估算撮合 | 未執行 | MarketData/TradingEngine E3 policy; full UI flow not yet executed |
| T43 | 交易／資產匯出 | 未執行 | networkWhitelistAndCSVInjection; dualAccountBackupAndCSVNumbers |
| T44 | 網路政策 | 通過 | networkWhitelistAndCSVInjection |
| T45 | 100,000 筆交易壓力資料 | 自動化通過；實機頁面效能未測 | run 40517887202: stressHistory100000; 100,000 fills + 100,001 equity points; 3 s repository load/report, 300 ms page p95, 150 ms order p95; plan 2 s app cold launch unmeasured; full integrity/CSV/backup equality |
| T46 | 公開儲存庫乾淨建置 | 通過 | run 40517887202, clean checkout / no secrets / core + UI + device build |
| T47 | IPA 結構與簽署狀態 | 通過 | run 40517887202, verify_artifact.sh and IPA zip validation |
| T48 | 使用者簽署後實機操作 | 外部條件阻擋 | 需完整整合／UI／實機驗證 |

版本證據：TEST_EVIDENCE.json 記錄測試來源 SHA-256；Actions artifacts 包含每次 commit 的測試與建置日誌。T45 的新量測見 STRESS_REPORT.json；未把 Linux 結果冒稱為 iPhone 實機結果。


## 使用者新增產品驗收（持續補完，與原T01–T48並列）

| ID | 驗收 | 目前證據與狀態 |
|---|---|---|
| P01 | 全新A／B與舊身份、資產及委託安全遷移 | 真實身份125核心及全新UI已測；舊B持倉／日誌／自選增量遷移核心通過。舊A規則保留／無持倉明確升級新測試待此輪完成。完整既有帳戶UI仍待補。 |
| P02 | BTC、ETH、2330三主要操作可找到 | 40559942622：首頁2330進入、BTC首頁及ETH搜尋可到達；完整加密新聞案例後半失敗，整體仍部分通過。 |
| P03 | 股票／現貨／合約分離及對應交易文案 | 核心目錄、股票買賣1000股UI通過；現貨BTC及合約分類已實際到達，其他完整流程仍待驗收。 |
| P04 | 可見列表多商品載入、批次／快取／去重／來源配額 | 排程及HTTP預算核心通過；fresh A UI實際BTC、ETH兩商品取得公開行情，缺Key股票不可操作，40559942622通過。 |
| P05 | 缺Key、401／403、429、斷線、過期、休市、恢復 | 錯誤與成交約束核心測試；BTC/ETH真實持續摘要／K線／恢復及本機委託E2E通過。每個錯誤的完整原生UI與實際受限來源仍待，fixture不算實連。 |
| P06 | B自動離線新聞、因果、不可偷看未來、帳務冪等 | 多類事件／發布時間／價格量能流動性／股息分割共享ID、分批重啟核心通過；完整新聞詳情UI仍待。 |
| P07 | B不同參與者補單與使用者成交後續影響 | 10/20/30/60秒池、跨更新用量、冪等委託總量／扣款、影響ID、剪枝後歸檔圖表一致核心通過；完整補算及產品UI仍待重跑。 |
| P08 | 市場搜尋、分類、排序、位置、自選與重啟 | 核心獨立偏好通過；新UI重啟後切換失敗，SQLite確認ETH仍保存。已修穩定市場綁定／焦點，待重測，不列通過。 |
| P09 | 取消、滑下關閉、返回、連點、單次扣款、日誌與自選 | 原九例兩輪加額外下單兩輪保持120秒／例及全部斷言；40559942622原互動19/20通過、1次鍵盤後滑下關閉委託頁失敗；整組失敗，待完整重跑。上一輪超時及本輪失敗證據保留。 |
| P10 | 淺／深、大字體、長中文、鍵盤、小螢幕及safe area | 40559942622正常字體設定七組及首頁／資產底部通過。新ProductVisualTests與17Pro/SE3矩陣尚未執行。 |
| P11 | 橫向圖表及返回 | 40559942622實際截圖有旋轉圖表，但識別符傳給子元素使測試失敗；修正識別並驗證實際WebView及關閉入口，待重跑。 |
| P12 | 原2秒冷啟動／150ms門檻 | 全部保留。最新100項完整Release含原T45寫入p95=51.769125ms，Linux儲存測試；簽署iPhone正常B冷啟動與UI回饋仍無實機證據。 |
| P13 | 雙向／階梯／抵押／預估清算與各側資金費結算 | 核心精確帳務／風險／費用／重啟通過；原生風險操作與完整市場規則驗收仍待。 |
| P14 | 完整經濟現金流、歷史乘數及跨幣估值 | 現金流／分割／雙向周期／歷史乘數／SQLitev5遷移／備份v2核心通過；匯率有效期及更完整原生展示仍待補強。 |
| P15 | 官方合法商品探索、身份與來源限制 | Coinbase及官方Nasdaq Trader搜尋真實HTTP通過；ETF／交易所／代碼／名稱分頁和B禁止服務核心通過。Fugle/Alpaca/Twelve實際受限行情外部阻擋。 |
| P16 | 完整成品走查、逐頁前後圖、最新版IPA | 原21張已實際看圖、另有乾淨改版前CI圖。新產品完整走查及修正仍在進行；尚不宣告完整版或最終IPA交付。 |

原始使用者圖片底部未拍完整表示尚未往下捲動，並非已確認的導覽列遮擋缺陷。改版仍單獨實測安全區與底部可達性。

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
