# App1.2.25新增回歸編譯失敗

來源`ac124171af5624facf11211d247d3f7e2316cac5`，App1.2.25（28）。新增的取消瀏覽寫入回歸有三處把會拋錯的`repo.load()`直接放入`#require`，巨集展開後缺少內層`try`，因此兩組核心在編譯測試時失敗，沒有執行186項測試，也未執行本提交T45或大型封存。

原始工作與完整附件先保留：產品工作123200717998／[CI40798519710](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40798519710)，artifact12864154051，SHA256 `11c35a947dea2eda0e3f42ad561f51a8505b60600c482d25276f67547b90dd47`；導航工作123200718117／[CI40798519732](https://github.com/Kongdean2374/ChaiTrade/actions/runs/40798519732)，artifact12864358697，SHA256 `3c08121327f4e78aef48009bcc01cdbf412a1740714d49c45f8f21ae60f1d6e9`。

修正先以`try`讀取可選快照，再把已求值的可選值交給`#require`。取消必須拋CancellationError、記憶體及磁碟完整原值一致、後續提交成功及帳務不變等斷言全部保留，沒有刪除新增或原有測試。App1.2.26（29）須以同一提交完整重跑186核心兩組、實際HTTP、原T45、大型封存、Apple編譯、80UI與實際原圖；前版其他工作即使通過也不借作本版驗收。
