# ChaiTrade

原生 iOS 多市場模擬交易 App，依 [完整開發計劃書](docs/REQUIREMENTS.md) 開發。預設臺灣繁體中文、iOS 18 以上，無自有後端。

- **A**：真實行情、本機模擬委託；無權限或過期資料不成交。
- **B**：完全離線的決定性市場，內建 120 個可交易商品及 5 個參考指數。
- A／B 使用不同 SQLite 資料庫，模式切換於下次完整程序啟動生效。
- 所有資金、委託、成交與資產均為模擬。沒有真實下單、轉帳或錢包功能。

目前開發與驗證狀態見 [IMPLEMENTATION_STATUS](docs/IMPLEMENTATION_STATUS.md) 及 [未完成與無法實測項目](docs/REMAINING_WORK.md)。**建置成功不代表計劃書全部功能或實機驗收已完成。**

最新交付（2026-10-27）：[未簽名 IPA](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202/artifacts/12742124659) · [完整測試報告](docs/TEST_REPORT.md) · [Actions 40517887202](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202)。71 項核心測試跨必要關卡執行，九項 UI 各兩次及額外下單專測兩次全數通過，20 個獨立資料目錄；實機、舊 iOS18.x 完整互動及計劃書剩餘缺口仍未完成。

## 不需要 Mac 的建置方式

1. 開啟本倉庫的 **Actions → Build unsigned IPA → Run workflow**，選 `main`。
2. 等待核心測試、必要的十萬筆 Release 效能／對帳／備份關卡、iPhone 模擬器 UI 測試、iPhoneOS Release 編譯和產物檢查。
3. 從成功執行頁下方 **Artifacts** 下載 `ChaiTrade-unsigned-ipa`。
4. 解壓得到 `ChaiTrade-unsigned.ipa`、`.sha256`、`build-info.json` 及測試摘要。
5. 使用自己的有效裝機簽署方式重新簽署，再安裝至 iPhone。未簽名 IPA 無法直接安裝。

公開倉庫的程式變更也會自動觸發此流程。CI 不需要 Apple 登入、簽署憑證或付費行情金鑰。產物保留 7 天。

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

A 的行情來源只讀取資料，金鑰保存在裝置 Keychain；B 不讀取金鑰或建立 Provider。A 的費率、交易日曆與契約規格尚需核對現行市場制度，畫面明示為自訂模擬規則。行情供應商方案與地區限制依實際權限。

切換簽署 Team／Bundle ID 或重裝前，請先匯出帳戶備份；資料容器及 Keychain 不保證隨任意重簽保留。詳見 [建置與安裝](docs/BUILD_AND_INSTALL.md)、[已知限制](docs/KNOWN_LIMITATIONS.md)。
