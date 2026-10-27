import SwiftUI
import ChaiTradeCore

extension AppModel{
    func startFailedFileArchiveRecovery(_ url:URL,password:String,target:Mode){
        guard state==nil,engine==nil,!loading,!fileArchiveWorking else{return}
        fileArchiveWorking=true;fileArchiveCanCancel=true;fileArchiveProgress=0;fileArchiveGeneration=UUID();fileArchivePhase="驗證完整封存與帳本…"
        fileArchiveOperation=Task{
            let work=root.appendingPathComponent("file-work/"+UUID().uuidString),stage=work.appendingPathComponent("restored")
            let access=url.startAccessingSecurityScopedResource()
            defer{if access{url.stopAccessingSecurityScopedResource()};try? FileManager.default.removeItem(at:work);fileArchiveWorking=false;fileArchiveCanCancel=true;fileArchiveOperation=nil}
            do{
                let progress=fileProgress(fileArchiveGeneration)
                let worker=Task.detached(priority:.utility){try StreamingArchiveService.validate(url,stagingRoot:stage,expectedMode:target,password:password.isEmpty ? nil:password,progress:progress)}
                _=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
                try Task.checkCancellation();guard state==nil,engine==nil else{throw TradeError.wrongAccount}
                fileArchiveCanCancel=false;fileArchivePhase="套用已驗證帳戶並重新啟動…"
                let replacement=stage.appendingPathComponent("accounts/\(target.accountID)")
                let install=Task{@MainActor in try await self.finishFileRecovery(replacement:replacement,target:target)};try await install.value
                fileArchiveProgress=1;fileArchivePhase="完整帳戶已恢復；原目錄保留。"
            }catch is CancellationError{notice="恢復已取消；原帳戶目錄保留。"}catch{self.error=error.localizedDescription}
        }
    }
    private func beginFileOperation(_ body:@escaping @MainActor ()async throws->Void){
        guard !fileArchiveWorking,!exportingWork,!interactionBlocked,engine != nil,context != nil else{error="帳戶仍在處理其他工作，請完成後再建立或還原封存。";return}
        fileArchiveWorking=true;fileArchiveCanCancel=true;fileArchiveProgress=0;fileArchiveGeneration=UUID()
        fileArchiveOperation=Task{
            defer{fileArchiveWorking=false;fileArchiveCanCancel=true;fileArchiveOperation=nil;maintainingAccount=false}
            do{try await body()}catch is CancellationError{notice="檔案操作已取消；原帳戶資料保留。"}catch{self.error=error.localizedDescription}
        }
    }
    func cancelFileArchive(){guard fileArchiveCanCancel else{return};fileArchivePhase="正在取消並清理暫存…";fileArchiveOperation?.cancel()}
    private func fileProgress(_ generation:UUID)->@Sendable(Double)->Void{
        { [weak self] value in Task{@MainActor in guard let self,self.fileArchiveWorking,self.fileArchiveGeneration==generation else{return};if abs(value-self.fileArchiveProgress)>=0.005 || value>=1{self.fileArchiveProgress=value}} }
    }
    private func recoveryURL(_ purpose:String,context:AccountContext)->URL{
        root.appendingPathComponent("accounts/\(context.accountID)/snapshots/\(purpose)-\(Int64(Date().timeIntervalSince1970))-\(UUID().uuidString)/account.sqlite")
    }
    func startFileArchiveExport(password:String){
        beginFileOperation{
            guard let engine=self.engine,let context=self.context else{throw TradeError.wrongAccount}
            await self.flushBrowsing();try Task.checkCancellation()
            let work=self.root.appendingPathComponent("file-work/"+UUID().uuidString),snapshot=work.appendingPathComponent("source"),generation=self.fileArchiveGeneration
            defer{try? FileManager.default.removeItem(at:work)}
            self.maintainingAccount=true;self.fileArchivePhase="建立目前帳戶的一致性快照…"
            let token=try await engine.beginFileMaintenance(snapshotAt:snapshot.appendingPathComponent("accounts/\(context.accountID)/account.sqlite"),context:context)
            try await engine.endMaintenance(token:token,context:context);self.maintainingAccount=false
            let output=self.root.appendingPathComponent("share-cache/ChaiTrade-模擬交易-\(context.accountID)-\(UUID().uuidString).chaitradearchive"),progress=self.fileProgress(generation),time=self.now
            self.fileArchivePhase="整理、驗證並建立完整封存…"
            let worker=Task.detached(priority:.utility){try StreamingArchiveService.export(snapshotRoot:snapshot,mode:context.mode,to:output,password:password.isEmpty ? nil:password,time:time,progress:progress);return output}
            let url=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
            guard self.context==context else{throw TradeError.wrongAccount}
            self.fileArchiveURL=url;self.fileArchiveProgress=1;self.fileArchivePhase="封存已完成，可另存至檔案 App。"
        }
    }
    func startLocalRecoveryPoint(){
        beginFileOperation{
            guard let engine=self.engine,let context=self.context else{throw TradeError.wrongAccount}
            await self.flushBrowsing();try Task.checkCancellation();self.maintainingAccount=true;self.fileArchivePhase="建立本機恢復點…"
            let token=try await engine.beginFileMaintenance(snapshotAt:self.recoveryURL("manual",context:context),context:context)
            try await engine.endMaintenance(token:token,context:context);self.maintainingAccount=false;self.fileArchiveProgress=1;self.fileArchivePhase="本機恢復點已建立。"
        }
    }
    func localRecoveryPoints()->[URL]{
        guard let context else{return []}
        let directory=root.appendingPathComponent("accounts/\(context.accountID)/snapshots")
        return ((try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)) ?? []).compactMap{url in
            if url.pathExtension=="chaitrade"{return url}
            let database=url.appendingPathComponent("account.sqlite");return FileManager.default.fileExists(atPath:database.path) ? database:nil
        }.sorted{$0.path>$1.path}
    }
    func startFileArchiveRestore(_ url:URL,password:String,localPoint:Bool=false){
        beginFileOperation{
            guard let engine=self.engine,let context=self.context else{throw TradeError.wrongAccount}
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            if localPoint{
                let allowed=self.root.appendingPathComponent("accounts/\(context.accountID)/snapshots").resolvingSymlinksInPath().standardizedFileURL.path+"/"
                guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(allowed),url.pathExtension=="sqlite" else{throw TradeError.wrongAccount}
            }
            await self.flushBrowsing();try Task.checkCancellation()
            let work=self.root.appendingPathComponent("file-work/"+UUID().uuidString),stage=work.appendingPathComponent("restored"),generation=self.fileArchiveGeneration,progress=self.fileProgress(self.fileArchiveGeneration)
            defer{try? FileManager.default.removeItem(at:work)}
            self.maintainingAccount=true;self.fileArchivePhase="先保留目前帳戶的恢復點…"
            let token=try await engine.beginFileMaintenance(snapshotAt:self.recoveryURL("before-restore",context:context),context:context)
            do{
                self.fileArchivePhase="驗證封存、帳本與完整歷史…"
                let worker=Task.detached(priority:.utility){() throws->VerifiedAccountDatabase in
                    if !localPoint{return try StreamingArchiveService.validate(url,stagingRoot:stage,expectedMode:context.mode,password:password.isEmpty ? nil:password,progress:progress)}
                    return try LocalRecoveryService.stagePoint(url,stagingRoot:stage,mode:context.mode)
                }
                let verified=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
                try Task.checkCancellation();guard self.context==context,self.fileArchiveGeneration==generation else{throw TradeError.wrongAccount}
                self.fileArchiveCanCancel=false;self.fileArchivePhase="套用已驗證帳戶並重新載入…"
                try await engine.restoreVerifiedDatabase(verified,maintenanceToken:token,context:context)
                // Once committed, finish rebinding the new epoch even if the calling task is cancelled.
                let rebind=Task{@MainActor in try await self.rebindRestoredAccount()};try await rebind.value
                self.fileArchiveProgress=1;self.fileArchivePhase="還原完成；先前帳戶的恢復點已保留。"
            }catch{try? await engine.endMaintenance(token:token,context:context);throw error}
            await self.refresh();await self.ensureQuoteService();if self.tab==2{await self.loadChart()}
        }
    }
    func clearFileShareCache(){
        guard !fileArchiveWorking,!exportingWork else{return}
        do{let directory=root.appendingPathComponent("share-cache");if FileManager.default.fileExists(atPath:directory.path){try FileManager.default.removeItem(at:directory)};fileArchiveURL=nil;fileArchivePhase="已清除可重建的分享檔，帳戶與恢復點保留。"}catch{self.error=error.localizedDescription}
    }
    func startFileAccountReset(){
        beginFileOperation{
            guard let engine=self.engine,let context=self.context,let currency=self.state?.baseCurrency else{throw TradeError.wrongAccount}
            await self.flushBrowsing();try Task.checkCancellation();self.maintainingAccount=true;self.fileArchivePhase="先保存重設前的完整恢復點…"
            let token=try await engine.beginFileMaintenance(snapshotAt:self.recoveryURL("before-reset",context:context),context:context)
            do{
                let fresh=try TradingEngine.initial(mode:context.mode,baseCurrency:currency,capital:Amount("1000000"),time:self.now)
                try Task.checkCancellation();self.fileArchiveCanCancel=false;self.fileArchivePhase="重設目前帳戶並重新載入…"
                try await engine.restore(fresh,maintenanceToken:token,retireAfterRestore:true,context:context)
                let rebind=Task{@MainActor in try await self.rebindRestoredAccount()};try await rebind.value
                self.fileArchiveProgress=1;self.fileArchivePhase="目前帳戶已重設；另一帳戶與原恢復點保留。"
            }catch{try? await engine.endMaintenance(token:token,context:context);throw error}
        }
    }
}
