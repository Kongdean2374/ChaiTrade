# 互動 Bug 專項驗證

2026-10-27。程式版本 `998a2274f16bde9f6d76056d1e19e7b9c98c74ba` 的 [Actions 40517887202](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202) 已成功。互動專項包含兩次下單專測，再完整執行九案例各兩次，**20 次全部通過、零 UI 跳過、20 個獨立 UUID 資料目錄**。這不代表整份計劃書或實機驗收完成。

[最新版未簽名 IPA、checksum、build-info 與測試日誌](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202/artifacts/12742124659) · [完整 xcresult、畫面、狀態及資料庫證據](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202/artifacts/12743565956)。產物到期 `2026-11-03T14:45:18Z`；IPA SHA-256：`90d701b977efba1750c40c903b1a296d11cd72a2606a708f64882c73a2c9826c`。下載後仍需有效簽署才可安裝。

## 對抗性案例與資料隔離

每個測試先建立獨立 UUID 的 `ChaiTradeUITests/<UUID>` 目錄；五項專項核對 fixture 空帳戶，四項 smoke 於新目錄首次初始化；同案例內重啟使用相同 UUID，案例與重複執行間不共享資料。模式切換案例自行建立部位。正式 Release 忽略測試參數並使用正式資料根目錄。

| 案例 | 驗證內容 |
|---|---|
| 快速保存日誌 | 五連點，保存中關閉／滑下被擋；一筆且逐字一致；重啟仍一筆；相同文字的新草稿可另存一筆、ID 不同 |
| 快速下單／取消 | 多次開確認、取消零副作用；五連點確認，保存中關閉／滑下被擋；委託／成交／數量／部位各一次，現金與帳本精確對帳，重啟不重扣；成交後切頁與返回可操作 |
| Tab／自選 | 四個自選意圖全部收到且至少兩個非同步等待重疊；精確奇偶結果；再加入一項，連切與重點 Tab、重啟都保留 |
| 返回／彈窗／鍵盤 | 多層返回、邊緣返回、完成取消、滑下關閉；鍵盤開啟後必要按鈕可到達；未確認草稿與下單零副作用 |
| 補算中操作 | 面板已開時啟動真實補算；阻擋財務提交但可離開面板／切 Tab；連點暫停／繼續、位置固定、檢查點續算僅完成一次、零委託／成交且圖表更新 |

另保留四個獨立正常流程案例。每次失敗先附截圖、accessibility hierarchy、唯讀狀態 JSON；Actions always 收集 xcresult、日誌與僅限測試 UUID 的資料庫，才修正重跑。Debug 受控延遲只用於交錯測試，不宣稱效能；正式引擎及 SQLite 仍實際執行。

## 失敗與修正歷程

| Run | 結果及證據 | 判定／處理 |
|---|---|---|
| [40488978661](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40488978661) | 9 次，3 失敗；artifact12729017997；INTERACTION_BASELINE.json | 日誌重複且四筆空白、補算停用傳入面板屬產品 Bug。自選四連點實際只送三個意圖屬測試假設，改核對送達數並加原子切換。 |
| [40493670109](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40493670109) | UI 編譯失敗；artifact12730597113 | 明確指定 optional／比較式型別；未執行 UI，未宣稱通過。 |
| [40495754856](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40495754856) | 18 次，15 通過、3 失敗；artifact12732197033；INTERACTION_RETEST.json | 錄影確認繼續按鈕被暫停取代而連點誤觸；固定雙控制位置。下單先等可見送出中，保留不可關閉斷言。 |
| [40500836018](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40500836018) | 舊 iOS18.5 未完整通過；artifact12735000260；INTERACTION_ENVIRONMENT.json | 60 秒動畫通知遺失、Runner 重啟／終止錯誤、文字不符；保留失敗。逐字核對輸入、RunLoop 等待並結束 App；改以新 runtime 獨立驗證。 |
| [40506629626](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40506629626) | 新 runtime18 次，16 通過、2 下單失敗；artifact12736942115；INTERACTION_MODERN_RETEST.json | 快速點來源後底部確認 dialog 的取消無法定位；改置中明確確認 alert，保留取消與連點斷言。 |
| [40512460115](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40512460115) | 下單專測2次，1通過、1失敗；artifact12739490698；INTERACTION_ORDER_RETEST.json | 失敗時已顯示成交頁且資料一筆／一次扣款；selected Tab isHittable 判定不可靠。改實際成交頁＋關閉狀態及切頁往返驗證，並把切 Tab 延至面板 onDismiss。未宣稱重複扣款。 |
| [40516305173](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40516305173) | T45 寫入 p95 150.003375 ms 失敗；artifact12739162854；INTERACTION_T45_RETEST.json | 保留 150 ms 門檻；改用已驗證估值前綴的正式統計檢查點，僅計算新點，並新增逐點／重啟／回滾回歸。UI 與 IPA 上傳未執行。 |
| [40517887202](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40517887202) | 下單專測2次＋完整18次全部通過；INTERACTION_RESULTS.json | 所有快速操作、數量、金額、保存與重啟斷言保留，無失敗時產出中間 IPA。 |

原始 ZIP SHA-256 及機器結果在對應 JSON／TEST_EVIDENCE.json。失敗產物保留七天，關鍵數據也提交至 Git。完整結果和每例秒數見 [TEST_REPORT.md](TEST_REPORT.md)。

## 核心與驗收範圍

核心新增 48 次同請求 ID 並發下單僅一次成交／精確扣款及重啟冪等；32 次同草稿 ID 僅一筆、不同 ID 可同文字、空白拒絕；201 次跨商品原子自選切換、無效商品／舊 context 拒絕及重啟保存。本地完整 Release71 項零跳過，Apple 必要核心與 T45 關卡通過。

動畫保持開啟、九案例各兩次、另兩次下單專測、Xcode 單例 allowance120 秒、補算完成35 秒以及所有 T45 門檻均保留。測試時間包含受控等待及 XCTest 操作，不當作產品效能。

**未實測或未通過：** 舊 iOS18.x 完整兩輪互動、簽署實機、真實鍵盤／尺寸與完整無障礙矩陣及實機效能。新 iOS26.2 結果不能把舊 runtime 失敗改成通過；完整計劃書仍有 [剩餘缺口](REMAINING_WORK.md)。
