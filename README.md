# ChaiTrade

原生 iOS 多市場模擬交易 App，依 [完整開發計劃書](docs/REQUIREMENTS.md) 開發。預設臺灣繁體中文、iOS 18 以上，無自有後端。

- **A**：真實行情、本機模擬委託；無權限或過期資料不成交。
- **B**：完全離線的決定性市場，內建 120 個可交易商品及 5 個參考指數。
- A／B 使用不同 SQLite 資料庫，模式切換於下次完整程序啟動生效。
- 所有資金、委託、成交與資產均為模擬。沒有真實下單、轉帳或錢包功能。

目前候選App **1.2.19（22）**。行情 → 商品詳情仍留行情，明確買賣才進交易；交易獨立選商品與保存草稿，更新不重設帳戶。完整回歸與原圖驗收尚未完成，沒有本版IPA。

[使用說明](docs/PRODUCT_USER_GUIDE.md) · [產品對照](docs/PRODUCT_FEATURE_CROSSWALK.md) · [實際驗證](docs/VALIDATION_CURRENT.md) · [未完成與外部條件](docs/REMAINING_WORK.md)。**軟體通過不代表完整計劃或實機驗收已完成。**

本輪預期兩組184核心／實際公開HTTP／T45／大型封存與76次UI，必須同一提交完整重跑。前版失敗、逾時及未完成紀錄保留，不以舊綠燈替代；最新狀態見[驗證紀錄](docs/VALIDATION_CURRENT.md)。

## 不需要 Mac 的建置方式

1. 開啟本倉庫的 **Actions → Build unsigned IPA → Run workflow**，選 `main`。
2. 等待核心測試、必要的十萬筆 Release 效能／對帳／備份關卡、iPhone 模擬器 UI 測試、iPhoneOS Release 編譯和產物檢查。
3. 從成功執行頁下方 **Artifacts** 下載 `ChaiTrade-unsigned-ipa`。
4. 解壓得到 `ChaiTrade-unsigned.ipa`、`.sha256`、`build-info.json` 及測試摘要。
5. 使用自己的有效裝機簽署方式重新簽署，再安裝至 iPhone。未簽名 IPA 無法直接安裝。

公開倉庫的程式變更也會自動觸發此流程。CI 不需要 Apple 登入、簽署憑證或付費行情金鑰。產物保留 7 天。

App版本與建置號由 [version.json](version.json) 統一管理，設定／關於可查看安裝版本。新版產物另附 `ChaiTrade-版本-建置號-unsigned.ipa`，`build-info.json`記錄實際版本、建置號與commit。每次App更新同時增加版本與建置號，CI核對Info.plist及前一提交；不以改檔名代替真正升版。

## 開發

以 Xcode 26.2 開啟提交的 `ChaiTrade.xcodeproj`，選擇共享 Scheme `ChaiTrade`。原生 UI 為 SwiftUI，交易圖表使用隨 App 封裝的 Lightweight Charts 5.0.8。

```sh
bash scripts/preflight.sh
bash scripts/test.sh
bash scripts/test_ui.sh
bash scripts/build_unsigned_ipa.sh
```

核心可在 Swift 6.1 Linux 上測試，需 SQLite、OpenSSL 及 zlib 開發標頭。Linux 測試不代表 Apple 平台程式已編譯。重建 Xcode 專案：`python3 scripts/generate_project.py`。

## 使用界線

A 的行情來源只讀取資料，金鑰保存在裝置 Keychain；B 不讀取金鑰或建立 Provider。已核驗規則包、盤別及日曆有對應測試；更廣年份／特殊契約與來源映射仍按實際可得資料限制，不宣稱全市場皆已實連核驗。行情供應商方案與地區限制依實際權限。

切換簽署 Team／Bundle ID 或重裝前，請先匯出帳戶備份；資料容器及 Keychain 不保證隨任意重簽保留。詳見 [建置與安裝](docs/BUILD_AND_INSTALL.md)、[已知限制](docs/KNOWN_LIMITATIONS.md)。
