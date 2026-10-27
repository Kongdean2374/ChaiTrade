# 48 項驗收矩陣

本表的「通過」僅適用明列的核心自動化案例；不是整體實機驗收。測試來源位於 Packages/ChaiTradeCore/Tests/ChaiTradeCoreTests/ 及 ChaiTradeUITests/SmokeTests.swift 及 InteractionTests.swift。UI／IPA 狀態以 Actions 實際結果更新。外部憑證測試尚無使用者權限，不捏造成功。

| ID | 計劃書案例 | 狀態 | 方法與證據 |
|---|---|---|---|
| T01 | A 花 10,000、B 尚未交易 | 通過 | vectorAAndIsolation |
| T02 | 設定待切換後繼續本次使用 | 部分通過 | run 40517887202: pending mode keeps B banner/context; complete trading acceptance pending |
| T03 | 切到背景再回前景 | 部分通過 | run 40517887202: background/activate preserves mode; complete lifecycle acceptance pending |
| T04 | 目標帳戶資料庫或遷移故障 | 未執行 | 需完整整合／UI／實機驗證 |
| T05 | 舊行情回應延遲抵達 | 通過 | duplicateRequestAndEpoch |
| T06 | 首次安裝就飛航模式啟動 B | 未執行 | 需完整整合／UI／實機驗證 |
| T07 | A 無 API Key／無權限 | 外部條件阻擋 | 需完整整合／UI／實機驗證 |
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
