import SwiftUI
import UniformTypeIdentifiers

struct RecoveryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var password=""
    @State private var importing=false
    @State private var url: URL?
    @State private var confirm=false
    var body: some View {
        Form {
            Text("恢復目標：\((model.settings.pendingMode ?? model.settings.activeMode).label)").font(.headline)
            Text("先驗證備份、帳本與模式，再建立獨立暫存資料庫並取代無法啟動的帳戶目錄。舊目錄會保留在本機，另一帳戶不變。驗證失敗不會建立空帳戶覆蓋資料。").font(.footnote)
            SecureField("備份密碼（未加密可留空）",text:$password)
            Button("選擇帳戶備份"){importing=true}.disabled(model.loading || model.fileArchiveWorking)
            if model.loading{ProgressView("正在驗證與恢復…")}
            if model.fileArchiveWorking{Section{ProgressView(value:model.fileArchiveProgress);Text(model.fileArchivePhase).font(.caption);if model.fileArchiveCanCancel{Button("取消恢復",role:.cancel){model.cancelFileArchive()}}}}
            if let error=model.error{Text(error).font(.caption).foregroundStyle(.orange)}
        }.navigationTitle("帳戶恢復").toolbar{Button("完成"){dismiss()}.disabled(model.loading || (model.fileArchiveWorking && !model.fileArchiveCanCancel))}
            .interactiveDismissDisabled(model.loading || (model.fileArchiveWorking && !model.fileArchiveCanCancel))
            .onDisappear{if model.fileArchiveWorking && model.fileArchiveCanCancel{model.cancelFileArchive()}}
            .onChange(of:model.state?.accountID){_,account in if account != nil{dismiss()}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.data,.json]){result in switch result{case .success(let file):url=file;confirm=true;case .failure(let error):model.error=error.localizedDescription}}
            .confirmationDialog("以此備份恢復目標帳戶？",isPresented:$confirm,titleVisibility:.visible){Button("驗證並恢復",role:.destructive){if let url{Task{await model.recoverFailedAccount(url,password:password);if model.state != nil{dismiss()}}}}}
    }
}
