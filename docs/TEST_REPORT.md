# 測試報告

本版App **1.2.14（17）**，精確來源 `173d68397512d66aa5fdf22a2e7fe7b1e5f61156`。Apple Release及XCTest編譯、兩組178核心（含實際公開HTTP）、原十萬筆T45與大型封存，以及完整74次原生UI均已通過同提交核對。這不是整份計劃或實機驗收完成聲明，IPA還需原未簽名流程成功。

| 組別 | 實際執行 | 最長單例 | 獨立資料庫 | 原包 |
|---|---:|---:|---:|---|
| 行情／交易新流程 | 20/20 | 98.035s | 40 | [artifact 12821824919](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941053/artifacts/12821824919) |
| 原互動／冷啟動／補算 | 20/20 | 109.089s | 40 | [artifact 12824813783](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941103/artifacts/12824813783) |
| 完整產品旅程 | 17/17 | 99.75s | 36 | [artifact 12824985074](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941103/artifacts/12824985074) |
| 逐頁功能 | 5/5 | 114.086s | 10 | [artifact 12823586097](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941103/artifacts/12823586097) |
| SE深淺色／大字體／鍵盤 | 6/6 | 59.846s | 12 | [artifact 12824330700](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941103/artifacts/12824330700) |
| Pro深淺色／大字體／鍵盤 | 6/6 | 98.034s | 12 | [artifact 12824756502](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40700941103/artifacts/12824756502) |

原門檻未放寬；每次獨立乾淨資料，150份資料庫完整性與74個UUID關聯已查核。新流程20例包含2330／BTC／ETH行情內詳情、明確方向帶入、交易換商品、合法預填限價、草稿、重啟／返回／交錯回應、B唯讀刷新及鍵盤滑下。原20次互動保留日誌連點、下單一次、取消、Tab、A／B、補算等全部斷言。產品17例另含完整股票／現貨／合約、行情探索、新聞、通知、匯出與還原。

兩組十萬寫入p95 **57.968750ms／61.976167ms**；每組100000成交、100001估值點與30樣本，原150ms儲存門檻不變。超512MB加密封存核對320張合成測試附件原始位元。macOS儲存不等於iPhone2秒正常冷啟動或150ms操作回饋。

實際數值與流程原圖說明見[VALIDATION_CURRENT.md](VALIDATION_CURRENT.md)，逐例與原包SHA見[TEST_EVIDENCE.json](TEST_EVIDENCE.json)，原48項驗收及外部條件見[TEST_MATRIX.md](TEST_MATRIX.md)／[REMAINING_WORK.md](REMAINING_WORK.md)。歷史的成功、失敗、逾時與取消不改判，見[歷次失敗與修正](history/NAVIGATION_FAILURE_HISTORY_20261028.md)及[改版前測試報告](history/515b7da-TEST_REPORT.md)。
