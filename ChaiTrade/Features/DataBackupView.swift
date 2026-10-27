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
            Section("目前帳戶備份與還原") {
                if model.exportingWork{ProgressView("建立一致性備份中…")}
                SecureField("備份／還原密碼（可留空）",text:$backupPassword)
                Text("密碼備份使用 AES-256-GCM 與 PBKDF2-HMAC-SHA256（600,000 次）。密碼遺失無法恢復。API 金鑰不進備份。").font(.caption)
                Button("匯出目前帳戶備份"){Task{await model.export(kind:"backup",password:backupPassword)}}
                Button("完整備份 A 與 B（各自隔離）"){Task{await model.export(kind:"both",password:backupPassword)}}
                Button("選擇備份並驗證還原"){importing=true}
                Text("還原會先驗證模式、版本、校驗碼與帳本，再取代此帳戶。雙帳戶備份會取出符合目前模式的帳戶；另一帳戶保持不變。原帳戶會保存本機恢復點；A／B 不可交叉還原。").font(.caption).foregroundStyle(.secondary)
            }

        Section{NavigationLink("匯出紀錄與帳本"){DataToolsView()};NavigationLink("重設目前帳戶"){AccountResetView()}}
    }.navigationTitle("資料備份／還原")
        .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.json]){result in switch result{case .success(let url):restoreURL=url;confirmRestore=true;case .failure(let error):model.error=error.localizedDescription}}
        .confirmationDialog("以備份取代目前帳戶？",isPresented:$confirmRestore,titleVisibility:.visible){Button("確認驗證並還原",role:.destructive){if let url=restoreURL{Task{await model.importBackup(url,password:backupPassword)}}}}
    }
}
struct AccountResetView:View{
    @EnvironmentObject var model:AppModel
    @State private var resetStage=false
    @State private var resetText=""
    @State private var confirmReset=false
    var body:some View{Form{
        Section{Label("這會取代目前帳戶的所有資料",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.red);Text("請先匯出備份。只有目前帳戶會重設；另一帳戶保持隔離。執行前也會保存本機恢復點。");Button("準備重設 \(model.settings.activeMode.accountID)",role:.destructive){resetStage=true}}
        if resetStage{Section("二次確認"){TextField("輸入 RESET",text:$resetText).autocorrectionDisabled();Button("確認重設目前帳戶",role:.destructive){confirmReset=true}.disabled(resetText != "RESET" || model.interactionBlocked)}}
    }.navigationTitle("重設帳戶").confirmationDialog("確定重設此帳戶？",isPresented:$confirmReset,titleVisibility:.visible){Button("重設並保存恢復點",role:.destructive){Task{await reset()}}}}
    func reset() async {
        guard let engine=model.engine,let context=model.context else{return}
        await model.run{
            model.maintainingAccount=true;defer{model.maintainingAccount=false}
            let (token,current)=try await engine.beginMaintenance(context:context),time=model.now
            do{
            let backup=try await Task.detached{try BackupService.export(current,password:nil,time:time)}.value
            let dir=model.root.appendingPathComponent("accounts/\(context.accountID)/snapshots")
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
            try backup.write(to:dir.appendingPathComponent("before-reset-\(Date().timeIntervalSince1970).chaitrade"),options:.atomic)
            let fresh=try TradingEngine.initial(mode:context.mode,baseCurrency:current.baseCurrency,capital:Amount("1000000"),time:model.now)
            try await engine.restore(fresh,maintenanceToken:token,context:context);try await model.rebindRestoredAccount()
            model.clearChartCaches();model.stateRevision=UUID();resetStage=false;resetText="";model.notice="目前帳戶已重設；原資料有本機恢復點"
            }catch{try? await engine.endMaintenance(token:token,context:context);throw error}
        }
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
