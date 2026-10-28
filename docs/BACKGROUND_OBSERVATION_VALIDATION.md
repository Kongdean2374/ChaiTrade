# 背景與冷啟動模式切換：失敗保全與驗證方式

來源16c9e42／1.2.16（19），run40725134954／job122952270780 原互動20次為19通過、1失敗92.717秒，零逾時。40份SQLite完整性與20獨立A／B會話均核對成功；這不是整組通過。artifact12836325855，SHA256 `fde2b86f3a34212fa095b44afbc8f45fe2d7a9bb83dcb6c99866743a1a90f1ac`。

失敗為Smoke的pending-mode案例第二次執行。按Home後，原10秒輪詢未看到XCUIApplication的兩種背景enum之一；測試在後續冷啟動斷言之前停止，不能據此斷言帳戶切換錯誤或已通過。

先保存原包、日誌、原圖、AX及帳戶，再修測試觀察方式。已實看原PNG `1C79B657-B60B-419A-8F01-9C7C17FA633F.png`（SHA256 `887855d8b9ab015875bdf13d267cbead20cd0e9511b1e0c46b5b5300e0ef9cc9`），當時是系統Home畫面；新鮮App探針同時為foreground=false、mode=offline、同一session，AX仍有原PID57850、B模式與待下次啟動提示，部位仍為台積電1000股。這些證據支持原生狀態輪詢誤判，而非App未收到背景生命週期。

測試仍只按一次真正Home、同樣10秒期限，改為同時核對原生SpringBoard在前景、App生命週期foreground=false、原mode及相同獨立session，另保存觀察值。接著仍必須原程序恢復保持B，完整終止再啟動才變A，再選B完整啟動，保留原部位／帳務斷言及120秒單例門檻。沒有用fixture設定背景、不重按Home、不先殺程序掩蓋暖恢復，也沒有把failed改成passed。

此修正尚須新的同提交完整75次UI及核心／規模回歸。此文件不宣稱最新版已通過或可交付IPA。
