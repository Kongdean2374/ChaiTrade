import Foundation

public enum LocalRecoveryService{
    /// Native callers restrict this to this account's own recovery directory, never external raw SQL files.
    public static func stagePoint(_ source:URL,stagingRoot:URL,mode:Mode)throws->VerifiedAccountDatabase{
        guard !FileManager.default.fileExists(atPath:stagingRoot.path) else{throw TradeError.invalid("還原暫存目錄已存在")}
        _=try SQLiteArchiveDatabase.verify(source,mode:mode)
        var complete=false;defer{if !complete{try? FileManager.default.removeItem(at:stagingRoot)}}
        let url=stagingRoot.appendingPathComponent("accounts/\(mode.accountID)/account.sqlite")
        let reader=try AccountRepository.archiveReader(source,mode:mode);try reader.createArchiveSnapshot(at:url)
        let repository=try AccountRepository(root:stagingRoot,mode:mode)
        guard var state=try repository.load() else{throw TradeError.corrupt("本機恢復點缺少帳戶")}
        if mode == .online{state.quotes=[:];state.consumed=[:];_=try repository.save(state)}
        try repository.rebuildArchiveReports(state);try repository.prepareArchiveFile()
        let result=try SQLiteArchiveDatabase.verify(url,mode:mode);complete=true;return result
    }
}
