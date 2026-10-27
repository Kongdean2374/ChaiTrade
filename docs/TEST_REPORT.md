# 測試報告

2026-10-27。最新程式版本 `d9dcb046fd27178f3997168531c94999889f7258` 的 [Actions 40481713600](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40481713600) 已成功。計劃書與驗收門檻保留；本報告不代表全部 48 項驗收完成。

## 完整回歸與 IPA

- 本地 Swift 6.1.3 Release：`CHAI_STRESS=1 CHAI_LIVE=1`，67 項核心測試全部執行並通過，零跳過。涵蓋真實 Coinbase ticker／level2／candles 唯讀請求。
- Apple Xcode 16.4／Swift 6.1.2：65 項一般核心函數與正式 Coinbase adapter 通過；十萬筆壓力測試在後續必要的獨立 Release 關卡執行並通過。一般階段對該 opt-in 的 skipped 訊息不代表豁免：其 Release 結果必須成功，否則無法上傳 IPA。
- iPhoneOS Release 編譯、arm64 平台／最低 iOS 18.0／本機圖表資源／ZIP／未簽署狀態檢查通過。日誌明確為 `code object is not signed at all`。
- iPhone 16 Pro／iOS 18.5 模擬器四項 UI 測試全部通過，0 failures。模擬器 workaround 見 TOOLCHAIN_NOTES.md，裝置版仍以 iOS 18.0 為最低版本。

| UI 案例 | 結果 | 時間 |
|---|---|---|
| testChartScreenshotCanBeAttachedToLocalJournal | 通過 | 67.642 s |
| testOfflineMarketOrderUsesLocalEngine | 通過 | 29.564 s |
| testOfflineOnboardingAndNavigation | 通過 | 21.980 s |
| testPendingSwitchRequiresColdLaunchAndPreservesOfflinePosition | 通過 | 26.621 s |

截圖案例保留原有的儲存後匯出按鈕驗證，並額外驗證附件開關、有效草稿預覽及儲存後 PNG。沒有刪除失敗斷言、停用案例或放寬門檻。

[下載最新未簽名 IPA、checksum、build-info 及測試摘要](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40481713600/artifacts/12724585202)；[完整日誌／xcresult 證據](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40481713600/artifacts/12724340761)。產物到期 `2026-11-03T09:49:08Z`。下載 ZIP 後，內含 `ChaiTrade-unsigned.ipa` 及其 `.sha256`；裝機仍需使用者有效簽署。

## T45：100,000 筆成交加 100,001 個估值點

實際保留 100,000 筆成交及委託、200,002 筆帳務、100,001 個估值點。完整 CSV 逐位元組比對、完整備份還原／餘額對帳、50,000 個結束周期、日期區間與並行一致性快照全部通過。每日畫面只讀有上限的資料視窗，完整歷史仍可分頁／搜尋及還原。

| Apple Release 量測 | 結果 | 既有／新增自動化門檻 |
|---|---:|---:|
| Repository hot-state 載入 | 215.53 ms | ≤3,000 ms（既有儲存層關卡） |
| 每頁 100 筆 p95 | 9.00 ms | ≤300 ms |
| 真正撮合寫入 p95（完整讀取並行） | 133.61 ms | ≤150 ms |
| 完整 CSV | 0.9070 s | ≤3 s |
| 完整統計報表 | 0.0303 s | ≤3 s |

兩個 p95 均為 30 個樣本。Hot fill/order 各 100 筆、equity 1,000 點；完整資料不丟棄。原本完整序列化與寫入的瓶頸改由索引歷史、分頁、CSV 快取及原子報表／估值前綴解決。早先 CSV 5.16 s、統計 3.35 s 與加入估值資料後寫入 p95 0.5878 s 的失敗均已修正，未豁免。

**仍有耗時操作：** Apple 全量匯入 24.39 s、完整稽核重建 19.38 s，均為明確的背景操作，不冒稱畫面載入時間。本地參考量測保留於 TEST_EVIDENCE.json。機器可讀的最新 Apple 結果為 STRESS_REPORT.json。

## 測試範圍與未完成驗收

核心回歸還涵蓋 schema 1／2／3 中斷回滾與重試、不可變歷史／失敗追加原子性、相同時間穩定分頁、壓縮備份上限、維護鎖與一致性讀取、部位周期成本、精確 OHLC／日曆／DST、休市跨週末歷史分頁、日誌 PNG／偏好／通知隔離、離線費用與每日／到期結算、完整決定性狀態重播、同秒成交費用及負淨值回撤。

**實機目標尚未測量：** 計劃書的正常 B 冷啟動 ≤2 秒、送單回饋 p95 ≤150 毫秒、畫面流暢度、記憶體與耗電。儲存層基準及模擬器不能取代這些實機驗收。也尚未執行 iPhone 17 Pro 簽署安裝、鎖屏通知、完整無障礙與實際斷電遷移測試。

Fugle／Alpaca／Twelve Data 缺少合法憑證／方案；Binance 地區回應 HTTP 451，均不宣稱實際行情成功。未完成的官方市場規則、雙向持倉／階梯保證金、完整現金流績效、B 參與者／新聞因果、商品中心及通知功能見 [REMAINING_WORK.md](REMAINING_WORK.md)。TEST_MATRIX.md 的部分通過與未執行項目繼續保留。
