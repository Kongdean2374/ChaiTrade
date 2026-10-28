import SwiftUI
import UniformTypeIdentifiers
import ChaiTradeCore
struct DataBackupView:View{
    @EnvironmentObject var model:AppModel
    @State private var backupPassword=""
    @State private var importing=false
    @State private var confirmRestore=false
    @State private var restoreURL:URL?
    var body:some View{Form{
            Section("完整檔案封存"){
                Text("適合大型歷史與圖表附件，單獨保存目前帳戶。密碼沿用下方欄位；完成後請另存至檔案 App。請保持 App 在前景直到完成。").font(.caption).foregroundStyle(.secondary)
                if model.fileArchiveWorking{ProgressView(value:model.fileArchiveProgress);Text(model.fileArchivePhase).font(.caption);Button("取消檔案操作"){model.cancelFileArchive()}.disabled(!model.fileArchiveCanCancel)}
                else{Button("匯出完整檔案封存"){model.startFileArchiveExport(password:backupPassword)}.accessibilityIdentifier("exportFileArchive");Button("建立本機恢復點"){model.startLocalRecoveryPoint()}.accessibilityIdentifier("createRecoveryPoint")}
                if let url=model.fileArchiveURL{
                    ShareLink(item:url){Label("分享已完成的封存",systemImage:"square.and.arrow.up")}.accessibilityIdentifier("shareFileArchive")
                    if model.fileArchiveFiles.count>1{Picker("選擇分享封存",selection:Binding(get:{model.fileArchiveURL ?? url},set:{model.fileArchiveURL=$0})){ForEach(model.fileArchiveFiles,id:\.self){file in Text(archiveTitle(file)).tag(file)}}}
                    Text(archiveTitle(url)).font(.caption).foregroundStyle(.secondary)
                    Text("只列目前帳戶的完成封存，重啟後仍可分享。清除暫存只影響此帳戶，請先另存需要保留的封存。").font(.caption)
                    Button("清除目前帳戶分享暫存"){model.clearFileShareCache()}.disabled(model.fileArchiveWorking).accessibilityIdentifier("clearFileShareCache")
                }
                if !model.fileArchiveWorking,!model.fileArchivePhase.isEmpty{Text(model.fileArchivePhase).font(.caption).foregroundStyle(.secondary)}
                NavigationLink("本機恢復點"){LocalRecoveryPointsView()}.disabled(model.fileArchiveWorking)
            }
            Section("目前帳戶備份與還原") {
                if model.exportingWork{ProgressView("建立一致性備份中…")}
                SecureField("備份／還原密碼（可留空）",text:$backupPassword)
                Text("密碼備份使用 AES-256-GCM 與 PBKDF2-HMAC-SHA256（600,000 次）。密碼遺失無法恢復。API 金鑰不進備份。").font(.caption)
                Button("匯出目前帳戶備份"){Task{await model.export(kind:"backup",password:backupPassword)}}
                Button("完整備份 A 與 B（各自隔離）"){Task{await model.export(kind:"both",password:backupPassword)}}
                Button("選擇備份並驗證還原"){importing=true}
                Text("還原會先驗證模式、版本、校驗碼與帳本，再取代此帳戶。雙帳戶備份會取出符合目前模式的帳戶；另一帳戶保持不變。原帳戶會保存本機恢復點；A／B 不可交叉還原。").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.fileArchiveWorking)

        Section{NavigationLink("匯出紀錄與帳本"){DataToolsView()};NavigationLink("重設目前帳戶"){AccountResetView()}}
    }.navigationTitle("資料備份／還原")
        .task{model.refreshFileShareCache()}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.json]){result in switch result{case .success(let url):restoreURL=url;confirmRestore=true;case .failure(let error):model.error=error.localizedDescription}}
        .alert("以備份取代目前帳戶？",isPresented:$confirmRestore){Button("確認驗證並還原",role:.destructive){if let url=restoreURL{Task{await model.importBackup(url,password:backupPassword)}}};Button("取消",role:.cancel){restoreURL=nil}}message:{Text("先驗證完整備份，再保存目前帳戶的恢復點並還原。另一帳戶不變。")}
    }
    private func archiveTitle(_ url:URL)->String{
        guard let values=try? url.resourceValues(forKeys:[.creationDateKey,.fileSizeKey]) else{return "已完成封存"}
        let date=values.creationDate.map{$0.formatted(date:.abbreviated,time:.shortened)} ?? "建立時間未知"
        let size=values.fileSize.map{ByteCountFormatter.string(fromByteCount:Int64($0),countStyle:.file)} ?? "大小未知"
        return date+" · "+size+" · "+String(url.deletingPathExtension().lastPathComponent.suffix(8))
    }
}
struct LocalRecoveryPointsView:View{
    @EnvironmentObject var model:AppModel
    @State private var points:[URL]=[]
    @State private var selection:URL?
    @State private var confirm=false
    var body:some View{List{
        Section{Text("只列目前獨立帳戶的恢復點。還原前會驗證完整帳本，並先保存目前帳戶的新恢復點；不移轉到另一帳戶。").font(.footnote)}
        if model.fileArchiveWorking{ProgressView(value:model.fileArchiveProgress);Text(model.fileArchivePhase);Button("取消檔案操作"){model.cancelFileArchive()}.disabled(!model.fileArchiveCanCancel)}
        if points.isEmpty{ContentUnavailableView("尚無本機恢復點",systemImage:"clock.arrow.circlepath",description:Text("可返回建立恢復點；還原與重設前也會自動保存。"))}
        ForEach(points,id:\.self){url in Button{selection=url;confirm=true}label:{VStack(alignment:.leading,spacing:6){Text(pointTitle(url)).font(.subheadline);Text("驗證並還原").font(.caption).foregroundStyle(.secondary)}}.disabled(model.fileArchiveWorking).accessibilityIdentifier("recoveryPoint-"+(url.pathExtension=="sqlite" ? url.deletingLastPathComponent().lastPathComponent:url.lastPathComponent))}
    }.navigationTitle("本機恢復點").task{points=model.localRecoveryPoints()}.onChange(of:model.fileArchiveWorking){_,working in if !working{points=model.localRecoveryPoints()}}
        .alert("還原所選恢復點？",isPresented:$confirm){Button("確認驗證並還原",role:.destructive){if let selection{if selection.pathExtension=="sqlite"{model.startFileArchiveRestore(selection,password:"",localPoint:true)}else{Task{await model.importBackup(selection,password:"")}}}};Button("取消",role:.cancel){selection=nil}}message:{Text("將先保存目前帳戶的新恢復點，再驗證並還原所選資料。取消不會修改帳戶。")}
    }
    private func pointTitle(_ url:URL)->String{
        let name=url.pathExtension=="sqlite" ? url.deletingLastPathComponent().lastPathComponent:url.lastPathComponent
        let purpose=name.hasPrefix("before-reset") ? "重設前":name.hasPrefix("before-restore") ? "還原前":name.hasPrefix("manual") ? "手動建立":"舊格式恢復點"
        let date=(try? url.resourceValues(forKeys:[.creationDateKey]).creationDate).map{$0.formatted(date:.abbreviated,time:.shortened)} ?? "建立時間未知"
        return purpose+" · "+date
    }
}
struct AccountResetView:View{
    @EnvironmentObject var model:AppModel
    @State private var resetStage=false
    @State private var resetText=""
    @State private var confirmReset=false
    var body:some View{Form{
        if model.fileArchiveWorking{Section{ProgressView(value:model.fileArchiveProgress);Text(model.fileArchivePhase);Button("取消檔案操作"){model.cancelFileArchive()}.disabled(!model.fileArchiveCanCancel)}}
        Section{Label("這會取代目前帳戶的所有資料",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.red);Text("請先匯出備份。只有目前帳戶會重設；另一帳戶保持隔離。執行前也會保存本機恢復點。");Button("準備重設 \(model.settings.activeMode.accountID)",role:.destructive){resetStage=true}}
        if resetStage{Section("二次確認"){TextField("輸入 RESET",text:$resetText).autocorrectionDisabled();Button("確認重設目前帳戶",role:.destructive){confirmReset=true}.disabled(resetText != "RESET" || model.interactionBlocked)}}
    }.navigationTitle("重設帳戶").alert("確定重設此帳戶？",isPresented:$confirmReset){Button("重設並保存恢復點",role:.destructive){Task{await reset()}};Button("取消",role:.cancel){}}message:{Text("將以初始虛擬資金取代目前帳戶，執行前保留完整恢復點。另一帳戶不變。")}}
    func reset() async {
        model.startFileAccountReset();resetStage=false;resetText=""
    }
}
struct AdvancedDiagnosticsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{
        Section("資料與引擎"){
            LabeledContent("帳戶",value:model.context?.accountID ?? "未載入")
            if let sim=model.state?.simulation{LabeledContent("重播種子",value:String(sim.seed));LabeledContent("模型版本",value:sim.algorithm);LabeledContent("事件時間",value:String(sim.time))}
            NavigationLink("帳務、交割與市場事件"){AccountingToolsView()}
        }
        Section("行情診斷"){
            ForEach((model.state?.instruments ?? []).filter{model.state?.quotes[$0.id] != nil}){i in if let q=model.state?.quotes[i.id]{VStack(alignment:.leading,spacing:5){Text(i.name+" · "+i.symbol).font(.headline);Text(q.source+" · "+q.grade.rawValue+" · "+q.quality.rawValue).font(.caption);Text(q.coverage).font(.caption).foregroundStyle(.secondary)}}}
        }
        Section("引擎事件"){ForEach(Array((model.state?.events ?? []).suffix(100).reversed())){event in VStack(alignment:.leading,spacing:5){Text(event.kind).font(.caption.monospaced());Text(event.message).font(.caption);Text(Date(timeIntervalSince1970:TimeInterval(event.time)).formatted()).font(.caption2).foregroundStyle(.secondary)}}}
    }.navigationTitle("進階診斷")}
}
