# 從 GitHub 取得未簽名 IPA

1. 本公開倉庫 → Actions → **Build unsigned IPA** → **Run workflow**。
2. 核心測試、UI 測試、iPhoneOS Release build、資源／架構／簽署檢查皆成功後，下載 **ChaiTrade-unsigned-ipa** artifact。
3. 解壓，核對 `ChaiTrade-unsigned.ipa.sha256` 及 `build-info.json` 的 commit 和 SHA-256。
4. IPA 中應是 `Payload/ChaiTrade.app`，是 iPhoneOS arm64 產物，不是 Simulator App。
5. 使用自己的有效裝機簽署環境，配合裝置、描述檔及 Bundle ID 條件處理。專案不要求提供 Apple ID 或憑證給 CI。不保證任何第三方簽署服務永久可用。
6. 安裝到 iPhone，首次可直接選 B、輸入各帳戶本金，飛航模式下驗證圖表與模擬交易。

建置不需要 Mac；簽署工具的需求由你選擇的有效方式決定。未簽名 IPA 不能直接點擊安裝。

更新、換簽署 Team／Bundle ID 或重新安裝前，先從設定匯出 A／B 各自備份。Keychain 存取與 App 容器可能改變，行情金鑰須重新輸入。Artifacts 預設保留 7 天；到期可重新執行 workflow。

失敗時查看執行頁和 **ChaiTrade-test-evidence** artifact，不以失敗 build 的中間產物冒充可用 IPA。完整功能、裝機簽署及實機效能須分別驗證。
