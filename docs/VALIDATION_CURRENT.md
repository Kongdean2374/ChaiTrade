# 目前候選驗證紀錄

候選App1.2.29（32）。正常瀏覽錯誤警告已保留原PNG／SQLite／原包後修正：防抖計時與單一寫入者分開、合併待存變更、context／generation隔離，真正失敗保留待存與警告，後續成功才清除同一瀏覽警告。

原185核心與79次UI均保留，新增取消寫入回滾／重試核心及交錯搜尋／冷啟動UI，現為186核心兩組與80UI（導航23、原互動22、產品18、逐頁5、SE／Pro各6）。Apple編譯、實際HTTP、原T45／大型封存、完整UI與九階段／25組原圖審視均待本候選同提交完成；沒有IPA，main不更新。

原1.2.24導航22／Pro6／SE6原包通過，但實際畫面發現正常瀏覽保存警告，逐頁首例亦逾時；仍未通過整體驗收。原日誌／圖表PNG保存、缺回呼、帳務唯一性、備份、補算、行情與產品功能均保留，不以清空資料或放寬門檻修正。

[本輪原始失敗](evidence/RETAINED_1_2_24_BROWSING_AND_PAGE_FAILURES.md) · [未完成條件](REMAINING_WORK.md) · [原矩陣](TEST_MATRIX.md)。


本候選另修新增回歸的巨集編譯用法，以及合約同意改定位真實子Switch，保留所有同意／取消／重開歸零與開平倉／金融斷言。原1.2.24產品17通過／1失敗，逐頁4通過／1逾時／1未完成；1.2.25兩組核心是測試編譯失敗，不能冒充已執行。見[原始編譯失敗](evidence/RETAINED_1_2_25_TEST_COMPILE_FAILURE.md)及[原始操作失敗](evidence/RETAINED_1_2_24_BROWSING_AND_PAGE_FAILURES.md)。本候選186核心兩組／80UI及所有原門檻待同提交實跑，沒有IPA。


本候選已檢查同類交易草稿路徑，新增獨立單一寫入者與帳戶重綁定隔離，並修正已編輯表單改回初始值被忽略；原草稿冷啟動案例加強為交錯保存3→1→7，核心取消回滾同時涵蓋兩條儲存路徑。186核心與80UI總數不變，所有新舊斷言與原門檻仍待同提交完整實跑，沒有IPA。詳見[PREFERENCE_WRITER_VALIDATION.md](PREFERENCE_WRITER_VALIDATION.md)。


DEBUG交錯同步點設定真實旗標後會通知唯讀探針更新，修正舊快照無法觀察開始狀態；不硬設通過結果、不跳過SQLite、不放寬原等待。見[原失敗](evidence/RETAINED_1_2_25_BARRIER_OBSERVATION_FAILURE.md)。本候選完整186核心兩組／80UI／實際HTTP／原T45／封存／Apple編譯／原圖仍待同提交結果，沒有IPA。


本候選保留ETH精確身份第一列原斷言，在原案例120秒內新增5秒有界搜尋呈現及實體排序核對後才比較，仍執行原鍵盤捲動／ETC實際選取／自選與帳務不變；原120秒不放寬。見[原始過渡擷取與階層](evidence/RETAINED_1_2_28_SEARCH_PRESENTATION_FAILURE.md)。186核心兩組／80UI及所有關卡待本提交完整實跑，沒有IPA。
