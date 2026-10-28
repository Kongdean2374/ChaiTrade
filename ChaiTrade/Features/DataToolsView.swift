import SwiftUI
import ChaiTradeCore

struct DataToolsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{
        Section("匯出本機資料"){
            Text("由一致性快照逐筆寫入完整紀錄，包含已歸檔歷史。JSON含原日誌圖片，僅供資料閱讀；要還原帳戶請使用完整檔案封存。檔案未加密，請自行選擇私人的保存位置。").font(.caption).foregroundStyle(.secondary)
            if model.fileArchiveWorking{ProgressView(value:model.fileArchiveProgress);Text(model.fileArchivePhase).font(.caption);Button("取消資料操作"){model.cancelFileArchive()}.disabled(!model.fileArchiveCanCancel)}
            Button("匯出成交 CSV"){model.startDataFileExport(.fills)}.disabled(model.fileArchiveWorking).accessibilityIdentifier("exportDataFills")
            Button("匯出完整委託 CSV"){model.startDataFileExport(.orders)}.disabled(model.fileArchiveWorking).accessibilityIdentifier("exportDataOrders")
            Button("匯出資金帳本 CSV"){model.startDataFileExport(.ledger)}.disabled(model.fileArchiveWorking).accessibilityIdentifier("exportDataLedger")
            Button("匯出 JSON"){model.startDataFileExport(.json)}.disabled(model.fileArchiveWorking).accessibilityIdentifier("exportDataJSON")
            NavigationLink("資料備份／還原"){DataBackupView()}
        }
        if let url=model.dataShareURL{Section("已完成的資料檔"){
            ShareLink(item:url){Label("分享已完成的資料檔",systemImage:"square.and.arrow.up")}.accessibilityIdentifier("shareDataFile")
            if model.dataShareFiles.count>1{Picker("選擇資料檔",selection:Binding(get:{model.dataShareURL ?? url},set:{model.dataShareURL=$0})){ForEach(model.dataShareFiles,id:\.self){file in Text(fileTitle(file)).tag(file)}}}
            Text(fileTitle(url)).font(.caption).foregroundStyle(.secondary)
            Button("清除目前帳戶資料分享暫存"){model.clearDataShareCache()}.disabled(model.fileArchiveWorking).accessibilityIdentifier("clearDataShareCache")
        }}
        if !model.fileArchiveWorking,!model.fileArchivePhase.isEmpty{Text(model.fileArchivePhase).font(.caption).foregroundStyle(.secondary)}
        Section{NavigationLink("帳務、交割與市場事件"){AccountingToolsView()}}
        Section("最近資金帳本"){
            ForEach(Array((model.state?.ledger ?? []).suffix(40).enumerated()),id:\.offset){_,entry in HStack{VStack(alignment:.leading){Text(entry.account).font(.caption);Text(entry.currency).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(MarketText.number(entry.amount)).font(.caption.monospaced())}}
        }
    }.navigationTitle("資料工具").task{model.refreshDataShareCache()}}
    private func fileTitle(_ url:URL)->String{
        let values=try? url.resourceValues(forKeys:[.creationDateKey,.fileSizeKey])
        let date=values?.creationDate.map{$0.formatted(date:.abbreviated,time:.shortened)} ?? "建立時間未知"
        let size=values?.fileSize.map{ByteCountFormatter.string(fromByteCount:Int64($0),countStyle:.file)} ?? "大小未知"
        return url.pathExtension.uppercased()+" · "+date+" · "+size+" · "+String(url.deletingPathExtension().lastPathComponent.suffix(8))
    }
}
