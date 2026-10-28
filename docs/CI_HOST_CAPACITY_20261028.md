# 2026-10-28 CI 主機容量與重新驗證

目前 App 為 1.2.16（19）。此次只改 CI runner 標籤，沒有 App／Core 行為變更，不增加 App 版本。

## 已保留的未執行紀錄

- [來源 16c9e42，navigation run 40725134967](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40725134967)：core job 122946238409 等待 15m1s 後取消，未執行測試。GitHub 註記：`The job was not acquired by Runner of type hosted even after multiple attempts` 及 `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times.`
- 該來源第一組實測 181 項核心、真實公開 HTTP、T45、超 512MB 封存通過；另一組及完整 75 次 UI 未完成，不能宣稱整體通過。
- 更早 [075963c / product run 40715902175](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40715902175) 第一次排程也在執行前因相同容量問題失敗；第二次真正執行 T45 的 162.381875ms 失敗保留，不因排程問題或其他成功組改判。

## 最小 CI 修正與不變條件

三條驗證／交付 workflow 的 `runs-on` 從 ARM `macos-15` 改成標準 x64 `macos-15-intel`。不使用 larger runner、不購買資源、不變更帳戶設定。主機 CPU 架構必須在結果中明列，不能把新主機的效能冒充 iPhone 實測或 ARM 主機結果。

相同 macOS 15、固定 `/Applications/Xcode_26.2.app/Contents/Developer`、iOS 26.2 Simulator、iPhone 17 Pro 與 SE3；Release 仍為 generic iPhoneOS arm64。腳本原已按 `uname -m` 選取 Simulator 的主機架構。

不變更任何測試腳本、案例、斷言、獨立資料、重試行為或門檻：181 項核心、75 次 UI（21／20／17／5／6／6）、100000 成交／100001 估值點／30 樣本、150ms T45 寫入、每 UI 個案 120 秒、圖表 10 秒、補算 35 秒、原正常冷啟動 2 秒、未簽名交付原 UI step 35 分鐘全部保留。主機更換本身不算產品修復，也不算測試成功。

必須在新的同一提交重跑完整核心、實連、效能、大封存與 75 次 UI，重新下載核對原包、資料庫、獨立帳戶、逐例時間與原始截圖；舊來源的成功及截圖只保留為歷史，不能當新來源證據。實機、合法 Key／授權等既有外部阻擋不因此解除。

## 官方映像依據（2026-10-28 查核）

- [runner labels](https://github.com/actions/runner-images/blob/main/README.md)：macOS 15 x64 提供 `macos-15-intel`；ARM 為 `macos-15`。
- [macOS 15 Intel image](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md)：macOS 15.7.9、Xcode 26.2、iOS 26.2 SDK／Simulator 與相應裝置。
