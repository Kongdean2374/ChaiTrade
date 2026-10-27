import Foundation
import CSQLite

public struct JournalPageRow:Sendable,Identifiable{
    public let cursor:Int64
    public let entry:JournalEntry
    public var id:String{entry.id}
}

extension AccountRepository{
    static func validateJournal(_ j:JournalEntry,instrumentIDs:Set<String>,allowProjection:Bool)throws{
            guard !j.id.isEmpty,j.id.utf8.count<=128,j.time>=0,(j.screenshotBytes==nil)==(j.screenshotSHA256==nil) else{throw TradeError.corrupt("日誌身份或附件欄位不合法")}
            if let size=j.screenshotBytes,let hash=j.screenshotSHA256{guard (24...2_000_000).contains(size),hash.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,j.screenshot != nil || allowProjection else{throw TradeError.corrupt("日誌附件缺少實際內容")}
                if let image=j.screenshot{guard image.count==size,BackupService.digest(image)==hash else{throw TradeError.corrupt("日誌附件校驗不符")}}
            }
            guard j.text.utf8.count<=32_768,j.tags.utf8.count<=2048,(j.emotion?.utf8.count ?? 0)<=256,j.instrumentID==nil || instrumentIDs.contains(j.instrumentID!) else{throw TradeError.corrupt("日誌內容超過範圍或商品不符")}
            if let image=j.screenshot{
                guard image.count<=2_000_000,image.count>=24,Array(image.prefix(8))==[137,80,78,71,13,10,26,10] else{throw TradeError.corrupt("日誌截圖格式或大小不合法")}
                let bytes=Array(image.prefix(24)),width=bytes[16..<20].reduce(UInt32(0)){($0<<8)|UInt32($1)},height=bytes[20..<24].reduce(UInt32(0)){($0<<8)|UInt32($1)}
                guard width>0,height>0,width<=4096,height<=4096 else{throw TradeError.corrupt("日誌截圖尺寸超過安全範圍")}
            }
    }

    func createJournalSchema()throws{
        try exec("CREATE TABLE IF NOT EXISTS journal_entries(id TEXT PRIMARY KEY,account_id TEXT NOT NULL,time INTEGER NOT NULL,payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS journal_entries_time ON journal_entries(time); CREATE TABLE IF NOT EXISTS journal_images(id TEXT PRIMARY KEY REFERENCES journal_entries(id) ON DELETE CASCADE,bytes BLOB NOT NULL)")
    }
    func journalCountUnlocked()throws->Int{guard let n=Int(try scalar("SELECT count(*) FROM journal_entries") ?? ""),n>=0 else{throw TradeError.corrupt("日誌筆數無法核對")};return n}
    func journalProjectionUnlocked(limit:Int)throws->[JournalEntry]{try readRows(JournalEntry.self,sql:"SELECT payload FROM (SELECT rowid AS ordinal,payload FROM journal_entries ORDER BY rowid DESC LIMIT ?) ORDER BY ordinal",values:[String(limit)])}
    private func imageUnlocked(id:String)throws->Data?{
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT bytes FROM journal_images WHERE id=?",-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("日誌附件讀取失敗")};defer{sqlite3_finalize(statement)}
        _=id.withCString{sqlite3_bind_text(statement,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
        let status=sqlite3_step(statement);if status==SQLITE_DONE{return nil}
        guard status==SQLITE_ROW else{throw TradeError.corrupt("日誌附件讀取中斷")}
        let size=Int(sqlite3_column_bytes(statement,0));guard (24...2_000_000).contains(size),let bytes=sqlite3_column_blob(statement,0) else{throw TradeError.corrupt("日誌附件大小不合法")}
        return Data(bytes:bytes,count:size)
    }
    private func fullJournalUnlocked(_ metadata:JournalEntry)throws->JournalEntry{
        var entry=metadata
        if let expected=entry.screenshotBytes,let hash=entry.screenshotSHA256{
            guard let image=try imageUnlocked(id:entry.id),image.count==expected,BackupService.digest(image)==hash else{throw TradeError.corrupt("日誌附件遺失或校驗碼不符，原資料保留")};entry.screenshot=image
        }else{var count="";try visit("SELECT count(*) FROM journal_images WHERE id=?",values:[entry.id]){count=$0};guard count=="0" else{throw TradeError.corrupt("日誌含未登記附件")}}
        return entry
    }
    func fullJournalsUnlocked()throws->[JournalEntry]{try readRows(JournalEntry.self,sql:"SELECT payload FROM journal_entries ORDER BY rowid").map{try fullJournalUnlocked($0)}}
    func saveJournalsUnlocked(_ state:AccountState,replacing:Bool)throws{
        if !replacing,let count=state.history?.journalCount{guard try journalCountUnlocked()==count else{throw TradeError.corrupt("日誌寫入來源已過期，已回滾")}}
        for entry in state.journals{
            var metadata=entry
            if let image=entry.screenshot{metadata.screenshotBytes=image.count;metadata.screenshotSHA256=BackupService.digest(image)}
            metadata.screenshot=nil
            if entry.screenshot==nil,let expected=metadata.screenshotBytes,let hash=metadata.screenshotSHA256{
                guard let original=try readRows(JournalEntry.self,sql:"SELECT payload FROM journal_entries WHERE id=?",values:[entry.id]).first,original.screenshotBytes==expected,original.screenshotSHA256==hash else{throw TradeError.corrupt("日誌附件身份不符，不以空資料覆寫")}
            }
            try insert("INSERT INTO journal_entries(id,account_id,time,payload) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET time=excluded.time,payload=excluded.payload WHERE payload<>excluded.payload",[entry.id,state.accountID,String(entry.time),String(decoding:try Self.encode(metadata),as:UTF8.self)])
            if let image=entry.screenshot{
                var statement:OpaquePointer?
                guard sqlite3_prepare_v2(db,"INSERT INTO journal_images(id,bytes) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET bytes=excluded.bytes",-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("日誌附件寫入準備失敗")};defer{sqlite3_finalize(statement)}
                let a=entry.id.withCString{sqlite3_bind_text(statement,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
                let b=image.withUnsafeBytes{sqlite3_bind_blob(statement,2,$0.baseAddress,Int32(image.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
                guard a==SQLITE_OK,b==SQLITE_OK,sqlite3_step(statement)==SQLITE_DONE else{throw TradeError.corrupt("日誌附件寫入失敗，整筆交易已回滾")}
            }else if metadata.screenshotBytes==nil{try insert("DELETE FROM journal_images WHERE id=?",[entry.id])}
        }
    }
    func verifyJournalsUnlocked(_ state:AccountState)throws{
        guard let count=state.history?.journalCount else{return}
        let ids=Set(state.instruments.map(\.id));var seen=0
        try visit("SELECT payload FROM journal_entries ORDER BY rowid"){text in
            let entry=try JSONDecoder().decode(JournalEntry.self,from:Data(text.utf8)),full=try fullJournalUnlocked(entry)
            guard entry.screenshot==nil else{throw TradeError.corrupt("日誌目錄不應內嵌附件")}
            try Self.validateJournal(full,instrumentIDs:ids,allowProjection:false);seen+=1
        }
        guard seen==count else{throw TradeError.corrupt("日誌完整歷史筆數不符")}
        var invalid=""
        try visit("SELECT count(*) FROM journal_entries WHERE account_id<>? OR id IS NOT json_extract(payload,'$.id') OR time IS NOT json_extract(payload,'$.time')",values:[state.accountID]){invalid=$0}
        guard invalid=="0" else{throw TradeError.corrupt("日誌帳戶或身份不符")}
        try visit("SELECT count(*) FROM journal_images i LEFT JOIN journal_entries j ON j.id=i.id WHERE j.id IS NULL"){invalid=$0}
        guard invalid=="0" else{throw TradeError.corrupt("日誌含無來源附件")}
        let projected=try journalProjectionUnlocked(limit:20)
        guard try Self.encode(projected)==Self.encode(state.journals) else{throw TradeError.corrupt("日誌熱資料與完整歷史不符")}
    }
    public func journal(id:String)throws->JournalEntry?{
        lock.lock();defer{lock.unlock()}
        guard let entry=try readRows(JournalEntry.self,sql:"SELECT payload FROM journal_entries WHERE id=? AND account_id=?",values:[id,mode.accountID]).first else{return nil}
        return try fullJournalUnlocked(entry)
    }
    public func journalPage(limit:Int=20,before:Int64?=nil)throws->[JournalPageRow]{
        guard (1...100).contains(limit),before==nil || before!>0 else{throw TradeError.invalid("日誌分頁參數不合法")}
        lock.lock();defer{lock.unlock()}
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT rowid,payload FROM journal_entries WHERE rowid<? ORDER BY rowid DESC LIMIT ?",-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("日誌分頁讀取失敗")};defer{sqlite3_finalize(statement)}
        sqlite3_bind_int64(statement,1,before ?? Int64.max);sqlite3_bind_int(statement,2,Int32(limit))
        var rows:[JournalPageRow]=[],status=sqlite3_step(statement)
        while status==SQLITE_ROW{guard let text=sqlite3_column_text(statement,1) else{throw TradeError.corrupt("日誌資料遺失")};rows.append(JournalPageRow(cursor:sqlite3_column_int64(statement,0),entry:try JSONDecoder().decode(JournalEntry.self,from:Data(String(cString:text).utf8))));status=sqlite3_step(statement)}
        guard status==SQLITE_DONE else{throw TradeError.corrupt("日誌分頁讀取中斷")};return rows
    }
}
