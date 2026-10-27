# 2026-10-27 平台與歷史行情修正紀錄（持續驗證中）

本紀錄補充原 REQUIREMENTS、REMAINING_WORK、IMPLEMENTATION_STATUS、TEST_MATRIX；不取代原完整計劃，不宣告產品驗收完成。

## 已保留的失敗

- 產品 CI [40587436896](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40587436896)，來源 16ba6f0：iOS device / XCTest 編譯成功；17 Pro 視覺 4/4 通過；SE 視覺 2/4 通過（下單數量欄位及日誌入口仍失敗）；頁面證據 3/4（行情連線控制項名稱重複）。產品流程 7/8，快速切換／重新啟動例在終止 App 時失敗。完整原互動結果另行核實，不能把尚未完成的 job 計入通過。
- 此 CI 的 core 三例在 Apple SQLite 防護設定失敗，T45 因前一步失敗未執行。
- [40590393146](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40590393146) 修正擴充載入判斷後仍三例失敗；[40590870232](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40590870232) 記錄 SQLITE_CANTOPEN (14)，確定是唯讀讀取 WAL 快照問題。
- [40591290742](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40591290742) 與 [40591350835](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40591350835)：三個歸檔讀取問題修正，僅剩 Apple 遺留的 shm 檔檢查失敗；保持檢查要求，改為關閉獨立快照後移除廢棄索引，不動原帳戶。
- [40590624785](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40590624785)：新增期貨年月測試找出來源短碼年分擷取錯誤，已修正；原帳戶 ID／商品代碼不變，不能用連續近月替換。
- [40591888662](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40591888662)：131 例中歸檔／新增歷史皆通過，但實連行情時間檢查失敗；不能稱為全綠，T45 未執行。該例把排程等待前的時間當作接收時間，現在分開記錄 request / receipt / source / execution，保留 30 秒有效期與原 5 秒未來容差；超齡／未來價格仍拒絕。成功訊息不取代 XCTest 結果。

## 實作範圍

- Apple SQLite 3.43.2 診斷：DEFENSIVE enable/read 均 rc=0、flag=1；OMIT_LOAD_EXTENSION=1；關閉擴充載入 selector 回傳 21。只有明確的編譯移除才視為無載入器，其他平台必須成功關閉並驗證 flag=0。唯讀及精確 compiled schema 白名單保留。
- SQLite backup API 建立新獨立快照後切換為 rollback journal，關閉後清理該快照的廢棄 shm。原帳戶仍 WAL；不刪原帳戶日誌，不用檔案複製取代一致性備份。
- Fugle 股票歷史分鐘 K：有界日期分頁、跨空交易區間繼續、台北日期、整股分鐘張數轉股數，日線不再乘 1,000；零股僅用來源真正支援的當日日內資料。
- Fugle 一般月期貨：歷史商品 root + 完整契約年月 + 日／夜盤分開請求，驗證回應與逐根 contractMonth；日線以真實兩盤資料依先夜後日合併 OHLC／量，分鐘保留原時區時間戳，不製造零成交 K 線。週契約／價差／選擇權未納入此對應，不猜代碼。
- 匯入來源短碼只在來源提供完整結算年月且與短碼吻合時儲存 sourceContractMonth；既有持倉 ID 不改、不換商品、不重設。
- 歷史權限與當日日內權限分開：可用的真實當日圖仍可顯示，旁邊標歷史限制；429、連線、資料錯誤不做額外 fallback 請求。沒有 Key 的授權實連仍是「外部條件阻擋」，fixture 僅驗證協定。
- 圖表工作可取消；只有相同 account context／generation／selected 才能寫入畫面與快取；限制文字不取代可用圖表。
- 行情連線設定入口新增固定 accessibility identifier；reveal 在元素不存在時先保存失敗證據，未降低可達性要求。

## 驗收仍未完成

雲端工作區執行介面目前不可用，不能讀取尚未提交的串流大檔備份／本機恢復 UI 工作，也不能在工作區下載檢視最新 SE 失敗照片。原 artifact 已保留，未把照片轉存公開 Actions 日誌。自動審核拒絕此轉存，理由為可能暴露截圖內的敏感資訊。

尚須：整合並測串流歸檔與恢復 UI、>512MB 真實規模與 RSS、日誌附件與生命週期長期規模、SE 與快速重啟問題修正及全套互動重跑、每頁乾淨前後截圖與成品完整走查、最終對應來源的未簽名 IPA。付費行情憑證／權限及實體 iPhone 的原啟動／回饋效能另列外部阻擋；Linux／macOS 儲存與模擬器不能代替實機門檻。

## 來源

- [SQLite db_config](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html)、[SQLite compile options](https://www.sqlite.org/compile.html#omit_load_extension)、[SQLite read-only WAL](https://www.sqlite.org/wal.html#read_only_databases)。
- [Fugle 股票歷史 K](https://developer.fugle.tw/docs/data/http-api/historical/candles/)、[期權歷史 K](https://developer.fugle.tw/docs/data-futopt/http-api/historical/candles/)、[期權日內 K](https://developer.fugle.tw/docs/data-futopt/http-api/intraday/candles/)、[期權目錄](https://developer.fugle.tw/docs/data-futopt/http-api/intraday/tickers/)。
