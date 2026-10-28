# 原計劃T01–T48與新增流程驗收對照

應用程式1.2.14（17）／`173d68397512d66aa5fdf22a2e7fe7b1e5f61156`。本表逐項保留原48項；「核心」指所列可重播的測試範圍，不等於付費來源、整體產品或實機驗收。當前兩組178核心及實際HTTP／T45／大型封存通過；74原生UI（新20、原互動20、產品17、逐頁5、SE及Pro各6）全部同提交通過。

| ID | 原計劃驗收 | 目前軟體證據／範圍 | 尚缺條件 |
|---|---|---|---|
| T01 | A 花 10,000、B 尚未交易 | vectorAAndIsolation；精確帳務及A／B隔離 | 本提交兩組178項核心通過；不代表實機驗收 |
| T02 | 設定待切換後繼續本次使用 | pendingModeOnlyAtColdStart；Smoke冷啟動切換各兩次 | 實機流程未測；最新同提交UI通過 |
| T03 | 切到背景再回前景 | 新增前景時鐘A／B案例；原後台／重啟互動 | 真實鎖屏／背景系統行為未測 |
| T04 | 目標帳戶資料庫或遷移故障 | brokenDatabaseAndLedgerNeverReset；原地恢復點／還原、舊epoch回呼拒絕 | 實機程序被終止／斷電情境未測 |
| T05 | 舊行情回應延遲抵達 | duplicateRequestAndEpoch | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T06 | 首次安裝就飛航模式啟動 B | offlineRejectsNetworkAndReplayCheckpoint、完整125身份初始目錄與原生首次B探索 | 系統飛航開關及實機網路觀察未測 |
| T07 | A 無 API Key／無權限 | 缺Key原生頁面、不給錯誤下單；HTTP錯誤分類／退避受控測試 | 需合法Key的401／403實際來源仍外部阻擋 |
| T08 | A 僅取得延遲資料 | staleAndDelayedNeverFill；來源delayed／historical／auction狀態受控驗證 | 付費延遲來源未取得實連權限 |
| T09 | 中斷報價／深度漏包 | sourceSpecificDepthGapRecovery；公開CB持續行情／K線／過期恢復實際HTTP | 其他受限來源實連恢復需Key；實機斷網未測 |
| T10 | 背景或斷線期間價格穿過停損 | 監測缺口不回填成交；quoted freshness／gap／重啟核心與前景測試 | 實際長時間背景與鎖屏停損觀察未測 |
| T11 | 多次點擊送單／事件重送 | duplicateRequestAndEpoch、並發同意圖重啟；原下單唯一性共4次及新增換商品一次成交 | 最新同提交74UI通過 |
| T12 | 多張委託同時保留相同資金 | reservationsAndCancel; partialCancelAndSharedLiquidity | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T13 | 部分成交後撤單 | partialCancelAndSharedLiquidity | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T14 | 分成多筆成交且有最低手續費 | minimumFeeNotRepeatedOnPartialFills; partialFillReleasesAlreadyPaidMinimumFeeReservation | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T15 | OCO 雙邊近乎同時觸發 | ocoAtomicAndReduceOnly | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T16 | 括號主單部分成交 | bracketFollowsActualFills; bracketPartialExitRemainsProtected | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T17 | Reduce-only 遇到部位減少 | reducedPositionCannotReverseOnSecondExit | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T18 | FOK／IOC／Post-only | fokAndIOC; postOnlyAndAtomicAmend | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T19 | 市價滑價或資金不足 | 資金保留、費用與流動性撮合有核心／現貨UI；未放寬精度或可用資金 | 市價跳空／耗盡各市場的完整UI組合尚未逐一實測 |
| T20 | 停損限價跳空 | stopLimitGapDoesNotGuaranteeFill | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T21 | 小數幣量、多次加減與捨入 | exactDecimalAndSerialization、現貨往返依每筆成交精確核對現金／費用 | 全面小數邊界UI組合未逐一實測 |
| T22 | 超大本金、非法精度或乘法溢位 | exactDecimalAndSerialization | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T23 | 缺少匯率／估值價格 | moneyFlowIsNotProfitAndFXIsIncomplete | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T24 | 人工入金／減資 | moneyFlowIsNotProfitAndFXIsIncomplete | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T25 | 逐倉／全倉與調整保證金 | fundingReplayAndMarginAdjustment、跨幣隔離、逐倉調整冪等、風險預覽與提款約束核心 | 完整逐倉／全倉／雙向／級距編輯所有UI組合未逐一實測 |
| T26 | 資金費率、借貸利息重啟重播 | offlineFundingScheduleIsExactSignedAndReplaySafe; fundingReplayAndMarginAdjustment; source entitlements pending | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T27 | 強平與穿倉 | derivativeNotionalIsNotAnAssetAndLiquidationKeepsDeficit | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T28 | 每日／到期結算 | futureSettlementResetsBasisAndExpires; offlineDailyAndFinalSettlementAreAtomicAcrossRestart; missing-DST-time schedule | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T29 | 分割／反向分割／股息 | splitVectorDAndDividendIdempotency; corporateSplitDoesNotRewriteOfflineHistory | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T30 | 日光節約時間、休市與零股盤 | 已核驗盤別／TWSE與NYSE日曆、T+2、跨日、半日市、DST、零股核心與單位原生頁面 | 更廣年份／特殊契約／全部來源映射未核驗 |
| T31 | B 固定種子連續執行與多次重啟 | offlineRejectsNetworkAndReplayCheckpoint | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T32 | B 多看圖／改週期／增載歷史 | deterministicCatalogAndTimePaths | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T33 | B 當前 K 線 | deterministicCatalogAndTimePaths | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T34 | B 1× 與 100× 推到同一模擬時間 | 固定時間路徑及補算對一般推進每個金融步進／檢查點比對；新增B實際播放／暫停 | 實機1×／100×長時間逐點完整驗收未測 |
| T35 | B 離開補算到一半被終止 | 原UI補算暫停／恢復兩次；原子檢查點重啟與事件重播核心 | 真正系統殺程序或斷電中止未測 |
| T36 | B 切到 A 一段時間後再切回 | 原A／B冷啟動保持部位兩次；固定seed／離線時鐘、備份及事件冪等核心 | 實機長時間切A後回B的完整補算未測 |
| T37 | 調整手機時間與時區 | DST／交易時段與時鐘倒退／七日警告程式、順序補算防護 | 實際更改手機時間／時區驗收未測 |
| T38 | A／B 備份還原與完整重設 | dualAccountBackupAndCSVNumbers、串流完整封存、恢復點取消／還原、舊epoch防護 | 真實檔案挑選器／檔案保護／重設全部實機流程未測 |
| T39 | 壞備份、錯密碼、錯模式、路徑穿越 | backupRoundTripEncryptionTamperingAndWrongMode | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T40 | schema 遷移被中斷 | injected failures/retries for schema 1, 2 and 3; physical termination acceptance pending | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T41 | 指數商品與資料缺失功能 | 指數不可下單、目錄分類、無權限商品仍可瀏覽與原生缺Key案例 | 所有指數／不同來源缺資料UI組合未逐一實測 |
| T42 | E3 參考價估算撮合 | E3參考價政策及不補造五檔；離線估算允許設定、期貨風險價防護 | 所有來源E3完整原生送單組合未逐一實測 |
| T43 | 交易／資產匯出 | 完整JSON／CSV保留歸檔、原圖片、離線衝擊；原生匯出、重啟、清暫存及備份隔離 | 實機系統分享目的地未測 |
| T44 | 網路政策 | networkWhitelistAndCSVInjection | 本提交兩組178核心通過；核心範圍不代表所有UI／實機均已驗收 |
| T45 | 100,000 筆交易壓力資料 | 十萬成交／100001估值點、30樣本，完整查核／CSV／備份及有界熱載入；新版兩組寫入p95為57.968750／61.976167ms | macOS儲存不代替原iPhone2秒冷啟動或150msUI回饋 |
| T46 | 公開儲存庫乾淨建置 | 公開原repo乾淨checkout、離線資源／秘密格式／版本檢查及Apple裝置／UI編譯 | 同提交軟體必要關卡通過；簽署實機條件仍待取得 |
| T47 | IPA 結構與簽署狀態 | 原未簽名流程及結構／簽署檢查保留；本版尚未產IPA | 先完成當前74UI及必要測試，再建置並核對commit／version／SHA |
| T48 | 使用者簽署後實機操作 | 外部條件阻擋 | 需要合法簽署及目標實體iPhone；不以模擬器代替 |

新增NF01–NF09及使用者產品要求不取代原48項：行情內詳情、精確買賣handoff、交易獨立選擇器、草稿衝突、刷新／限流、前景時鐘、B播放暫停、鍵盤下拉、原互動、完整產品與雙尺寸視覺，共74次原生執行均須同提交完成。每例使用獨立乾淨資料；120秒單例、10秒圖表、35秒補算、150ms寫入／回饋與2秒實機門檻均不變。

最新數值、CI、圖片、失敗分類與外部條件見[目前驗證](VALIDATION_CURRENT.md)；逐頁功能見[產品對照](PRODUCT_FEATURE_CROSSWALK.md)。原始48項要求保留；歷史失敗見[失敗與修正](history/NAVIGATION_FAILURE_HISTORY_20261028.md)，不重標舊結果。
