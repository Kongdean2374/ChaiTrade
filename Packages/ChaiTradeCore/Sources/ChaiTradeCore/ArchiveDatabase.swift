import Foundation
import CSQLite
#if canImport(CryptoKit)
import CryptoKit
#else
import COpenSSL
#endif

final class ArchiveDigest{
    #if canImport(CryptoKit)
    private var value=SHA256()
    #else
    private let value:OpaquePointer
    #endif
    private var finished=false
    init()throws{
        #if !canImport(CryptoKit)
        guard let context=EVP_MD_CTX_new() else{throw TradeError.unavailable("無法建立檔案校驗")}
        guard EVP_DigestInit_ex(context,EVP_sha256(),nil)==1 else{EVP_MD_CTX_free(context);throw TradeError.unavailable("檔案校驗初始化失敗")};value=context
        #endif
    }
    deinit{
        #if !canImport(CryptoKit)
        EVP_MD_CTX_free(value)
        #endif
    }
    func update(_ data:Data)throws{
        guard !finished else{throw TradeError.corrupt("校驗已完成")}
        #if canImport(CryptoKit)
        value.update(data:data)
        #else
        guard data.withUnsafeBytes({EVP_DigestUpdate(value,$0.baseAddress,data.count)})==1 else{throw TradeError.corrupt("檔案校驗失敗")}
        #endif
    }
    func finish()throws->String{
        guard !finished else{throw TradeError.corrupt("校驗已完成")};finished=true
        #if canImport(CryptoKit)
        return value.finalize().map{String(format:"%02x",$0)}.joined()
        #else
        var bytes=[UInt8](repeating:0,count:64),length:UInt32=0
        guard EVP_DigestFinal_ex(value,&bytes,&length)==1,length==32 else{throw TradeError.corrupt("檔案校驗失敗")}
        return bytes.prefix(Int(length)).map{String(format:"%02x",$0)}.joined()
        #endif
    }
    static func file(_ url:URL)throws->String{
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};let digest=try ArchiveDigest()
        while let block=try handle.read(upToCount:1_048_576),!block.isEmpty{try Task.checkCancellation();try digest.update(block)}
        return try digest.finish()
    }
}
public struct VerifiedAccountDatabase:Sendable{
    public let mode:Mode
    public let url:URL
    public let digest:String
    public let state:AccountState
    init(mode:Mode,url:URL,digest:String,state:AccountState){self.mode=mode;self.url=url;self.digest=digest;self.state=state}
}
enum SQLiteArchiveDatabase{
    static func copy(source:OpaquePointer,target:OpaquePointer,interrupt:(()throws->Void)?=nil)throws{
        guard let backup=sqlite3_backup_init(target,"main",source,"main") else{throw TradeError.unavailable("無法開始一致性檔案複製；原帳戶保留")}
        var complete=false
        defer{if !complete{sqlite3_backup_finish(backup)}}
        var busy=0
        while true{
            try Task.checkCancellation();try interrupt?()
            let code=sqlite3_backup_step(backup,64)
            if code==SQLITE_DONE{break}
            if code==SQLITE_BUSY || code==SQLITE_LOCKED{busy+=1;guard busy<50 else{throw TradeError.unavailable("資料庫正在使用，請稍後重試；原帳戶未被部分取代")}}
            else{guard code==SQLITE_OK else{throw TradeError.corrupt("帳戶檔案複製失敗，已回滾")};busy=0}
        }
        let code=sqlite3_backup_finish(backup);complete=true
        guard code==SQLITE_OK else{throw TradeError.corrupt("帳戶檔案複製未完成，原交易保留")}
    }
    static func visit(_ db:OpaquePointer,sql:String,values:[String]=[],body:(String)throws->Void)throws{
        var statement:OpaquePointer?;guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK,let statement else{throw TradeError.corrupt("歸檔查核無法準備")};defer{sqlite3_finalize(statement)}
        for (n,value) in values.enumerated(){guard value.withCString({sqlite3_bind_text(statement,Int32(n+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))})==SQLITE_OK else{throw TradeError.corrupt("歸檔查核參數無效")}}
        var status=sqlite3_step(statement)
        while status==SQLITE_ROW{try Task.checkCancellation();guard let text=sqlite3_column_text(statement,0) else{throw TradeError.corrupt("歸檔欄位遺失")};try body(String(cString:text));status=sqlite3_step(statement)}
        guard status==SQLITE_DONE else{throw TradeError.corrupt("歸檔查核中斷，原帳戶未變")}
    }
    static func strings(_ db:OpaquePointer,_ sql:String,values:[String]=[])throws->[String]{var rows:[String]=[];try visit(db,sql:sql,values:values){rows.append($0)};return rows}
    static func schema(_ db:OpaquePointer)throws->[String]{try strings(db,"SELECT type||char(31)||name||char(31)||tbl_name||char(31)||coalesce(sql,'') FROM sqlite_schema ORDER BY type,name")}
    static func verify(_ url:URL,mode:Mode)throws->VerifiedAccountDatabase{
        let templateRoot=url.deletingLastPathComponent().appendingPathComponent("schema-"+UUID().uuidString),template=try AccountRepository(root:templateRoot,mode:mode)
        defer{try? FileManager.default.removeItem(at:templateRoot)}
        let expected=try template.withArchiveConnection{try schema($0)}
        // Do not run repository migrations or schema creation against an imported file.
        let reader=try AccountRepository.archiveReader(url,mode:mode)
        try reader.withArchiveConnection{db in
            guard chai_sqlite_archive_defensive(db)==SQLITE_OK else{throw TradeError.corrupt("無法啟用唯讀歸檔防護")}
            // Older SQLite marks its own json_extract expression indexes unsafe with trusted_schema=OFF.
            // Inspect only sqlite_schema first, then permit the exact compiled schema's built-in indexes.
            // No imported views, triggers, virtual tables or custom SQL are accepted or evaluated.
            guard try strings(db,"PRAGMA user_version")==["6"],try schema(db)==expected else{throw TradeError.corrupt("歸檔資料庫版本或結構不符；不執行自訂SQL")}
            guard try strings(db,"PRAGMA quick_check")==["ok"],try strings(db,"SELECT count(*) FROM account_state")==["1"] else{throw TradeError.corrupt("歸檔資料庫完整性不符")}
        }
        guard let hot=try reader.load(),hot.mode==mode,hot.accountID==mode.accountID else{throw TradeError.wrongAccount}
        try verifyRows(reader,state:hot)
        try reader.verifyCapitalHistory(hot)
        return try VerifiedAccountDatabase(mode:mode,url:url,digest:ArchiveDigest.file(url),state:hot)
    }
    static func verifyRows(_ reader:AccountRepository,state:AccountState)throws{
        let instruments=Dictionary(uniqueKeysWithValues:state.instruments.map{($0.id,$0)}),decoder=JSONDecoder()
        try reader.withArchiveConnection{db in
            var lastSequence:Int64=0,cash:[String:Amount]=[:],totals:[String:FillTotals]=[:],metrics=EquityMetrics()
            for sql in [
                "SELECT count(*) FROM events WHERE account_id<>? OR id IS NOT json_extract(payload,'$.id') OR sequence IS NOT json_extract(payload,'$.sequence')",
                "SELECT count(*) FROM fills WHERE account_id<>? OR id IS NOT json_extract(payload,'$.id') OR order_id IS NOT json_extract(payload,'$.orderID') OR time IS NOT json_extract(payload,'$.time')",
                "SELECT count(*) FROM orders WHERE account_id<>? OR id IS NOT json_extract(payload,'$.id') OR status IS NOT json_extract(payload,'$.status') OR instrument IS NOT json_extract(payload,'$.request.instrumentID') OR time IS NOT json_extract(payload,'$.updatedAt')",
                "SELECT count(*) FROM ledger WHERE account_id<>?",
                "SELECT count(*) FROM equity WHERE account_id<>?",
                "SELECT count(*) FROM financial_flows WHERE account_id<>? OR id IS NOT json_extract(payload,'$.id') OR time IS NOT json_extract(payload,'$.time') OR sequence IS NOT json_extract(payload,'$.sequence')"
            ]{guard try strings(db,sql,values:[state.accountID])==["0"] else{throw TradeError.corrupt("歸檔列的帳戶或原始身份不符")}}
            try visit(db,sql:"SELECT payload FROM orders ORDER BY id"){text in
                let order=try decoder.decode(Order.self,from:Data(text.utf8)),request=order.request
                guard order.accountID==state.accountID,order.id==request.requestID,instruments[request.instrumentID] != nil,request.quantity > .zero,order.filled >= .zero,order.filled<=request.quantity,order.reserved >= .zero,order.referencePrice > .zero,request.leverage>=1 else{throw TradeError.corrupt("歸檔委託不合法")}
                if [.limit,.stopLimit].contains(request.kind){guard (request.price ?? .zero) > .zero else{throw TradeError.corrupt("歸檔限價遺失")}}
                if request.kind.conditional && request.kind != .trailing{guard (request.trigger ?? .zero) > .zero else{throw TradeError.corrupt("歸檔觸發價遺失")}}
                if request.kind == .trailing{guard (request.trailingDistance ?? .zero) > .zero else{throw TradeError.corrupt("歸檔追蹤距離無效")}}
                if request.postOnly{guard request.kind == .limit,request.price != nil else{throw TradeError.corrupt("歸檔Post-only無效")}}
                if let hot=state.orders[order.id]{guard try AccountRepository.encode(hot)==AccountRepository.encode(order) else{throw TradeError.corrupt("委託投影與歸檔不符")}}
                else if order.status.open{throw TradeError.corrupt("歸檔未結委託未包含於帳戶")}
            }
            var currentOrder:String?,order:Order?,filled=Amount.zero,fees=Amount.zero
            func finishOrder()throws{if let order{guard filled==order.filled,fees==order.fees else{throw TradeError.corrupt("歸檔成交與委託累計費用不符")}}}
            try visit(db,sql:"SELECT payload FROM fills ORDER BY order_id,rowid"){text in
                let fill=try decoder.decode(Fill.self,from:Data(text.utf8))
                if fill.orderID != currentOrder{
                    try finishOrder();currentOrder=fill.orderID;filled = .zero;fees = .zero
                    guard let raw=try strings(db,"SELECT payload FROM orders WHERE id=?",values:[fill.orderID]).first else{throw TradeError.corrupt("歸檔成交缺少委託")};order=try decoder.decode(Order.self,from:Data(raw.utf8))
                }
                guard fill.accountID==state.accountID,fill.quantity > .zero,fill.price > .zero,fill.fee >= .zero,fill.tax >= .zero,let instrument=instruments[fill.instrumentID],order?.request.instrumentID==fill.instrumentID else{throw TradeError.corrupt("歸檔成交不合法")}
                filled=try filled+fill.quantity;fees=try fees+fill.fee
                var total=totals[instrument.currency] ?? FillTotals();try total.include(fill);totals[instrument.currency]=total
            };try finishOrder()
            guard try AccountRepository.encode(totals)==AccountRepository.encode(Analytics.fillTotals(state)) else{throw TradeError.corrupt("歸檔成交統計不符")}
            try visit(db,sql:"SELECT payload FROM events ORDER BY sequence"){text in let event=try decoder.decode(AuditEvent.self,from:Data(text.utf8));guard event.sequence>lastSequence,event.sequence<=state.sequence,event.time>=0 else{throw TradeError.corrupt("歸檔事件順序不合法")};try event.capitalFlow?.validate();lastSequence=event.sequence}
            var group:String?,balance=Amount.zero
            try visit(db,sql:"SELECT payload FROM ledger ORDER BY json_extract(payload,'$.eventID'),json_extract(payload,'$.currency'),ordinal"){text in
                let entry=try decoder.decode(LedgerEntry.self,from:Data(text.utf8)),key=entry.eventID+"|"+entry.currency
                guard entry.accountID==state.accountID,!entry.eventID.isEmpty,entry.currency.range(of:"^[A-Z]{3,8}$",options:.regularExpression) != nil,entry.time>=0 else{throw TradeError.corrupt("歸檔帳本身份無效")}
                if group != key{guard balance == .zero else{throw TradeError.corrupt("歸檔帳本事件不平衡")};group=key;balance = .zero}
                balance=try balance+entry.amount;if entry.account=="cash"{cash[entry.currency]=try (cash[entry.currency] ?? .zero)+entry.amount}
            };guard balance == .zero,cash.filter({$0.value != .zero})==state.cash.filter({$0.value != .zero}) else{throw TradeError.corrupt("歸檔現金與帳本不符")}
            try visit(db,sql:"SELECT payload FROM equity ORDER BY ordinal"){text in let point=try decoder.decode(EquityPoint.self,from:Data(text.utf8));guard point.time>=0 else{throw TradeError.corrupt("歸檔估值時間無效")};metrics.consume(point)}
            guard try AccountRepository.encode(metrics)==AccountRepository.encode(Analytics.equityMetrics(state)) else{throw TradeError.corrupt("歸檔資金曲線統計不符")}
            try visit(db,sql:"SELECT payload FROM financial_flows ORDER BY rowid"){text in let flow=try decoder.decode(FinancialFlow.self,from:Data(text.utf8));guard flow.accountID==state.accountID,instruments[flow.instrumentID] != nil,flow.time>=0,flow.sequence>=0,flow.quantityRatio.map({$0 > .zero}) ?? true else{throw TradeError.corrupt("歸檔經濟流身份不合法")}}
            func verifyTail<T:Codable>(_ type:T.Type,table:String,order:String,offset:Int,expected:[T])throws{
                var index=0;try visit(db,sql:"SELECT payload FROM \(table) ORDER BY \(order) LIMIT ? OFFSET ?",values:[String(expected.count),String(offset)]){text in guard index<expected.count,try AccountRepository.encode(decoder.decode(type,from:Data(text.utf8)))==AccountRepository.encode(expected[index]) else{throw TradeError.corrupt("歸檔尾部投影不符")};index+=1};guard index==expected.count else{throw TradeError.corrupt("歸檔投影缺少歷史")}
            }
            try verifyTail(Fill.self,table:"fills",order:"rowid",offset:state.history?.fills ?? 0,expected:state.fills)
            try verifyTail(AuditEvent.self,table:"events",order:"sequence",offset:state.history?.events ?? 0,expected:state.events)
            try verifyTail(LedgerEntry.self,table:"ledger",order:"ordinal",offset:state.history?.ledger ?? 0,expected:state.ledger)
            try verifyTail(EquityPoint.self,table:"equity",order:"ordinal",offset:state.history?.equityOffset ?? 0,expected:state.equity)
            try verifyTail(FinancialFlow.self,table:"financial_flows",order:"rowid",offset:state.history?.financialFlowOffset ?? 0,expected:state.financialFlows ?? [])
        }
    }
}
