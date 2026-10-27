import Foundation
import CSQLite

public struct FillPageRow: Sendable,Identifiable {
    public let cursor: Int64
    public let fill: Fill
    public var id: String{fill.id}
}

/// Serial access is owned by TradingEngine. SQLite transactions protect the snapshot and idempotency indices.
public final class AccountRepository: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    public let mode: Mode
    public let path: String
    public init(root: URL, mode: Mode) throws {
        self.mode = mode
        let directory = root.appendingPathComponent("accounts/\(mode.accountID)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("account.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw TradeError.corrupt("無法開啟帳戶資料庫；原始資料保留") }
        do {
            try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA synchronous=FULL; PRAGMA busy_timeout=5000;")
            let version = try scalar("PRAGMA user_version") ?? "0"
            guard Int(version) ?? 99 <= 2 else { throw TradeError.corrupt("資料庫版本較新，請更新 App；不可降版覆寫") }
            try exec("BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS account_state (account_id TEXT PRIMARY KEY, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, sequence INTEGER NOT NULL UNIQUE, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS fills (id TEXT PRIMARY KEY, order_id TEXT NOT NULL, account_id TEXT NOT NULL, time INTEGER NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS fills_time ON fills(time); CREATE INDEX IF NOT EXISTS fills_order ON fills(order_id); CREATE INDEX IF NOT EXISTS fills_instrument_time ON fills(account_id,time); CREATE TABLE IF NOT EXISTS fill_report (id TEXT PRIMARY KEY REFERENCES fills(id), cells TEXT NOT NULL); CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, time INTEGER NOT NULL, instrument TEXT NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS orders_time ON orders(time); CREATE INDEX IF NOT EXISTS orders_time_id ON orders(time DESC,id DESC); CREATE INDEX IF NOT EXISTS fills_instrument ON fills(json_extract(payload,'$.instrumentID')); CREATE TABLE IF NOT EXISTS ledger (ordinal INTEGER PRIMARY KEY, account_id TEXT NOT NULL, payload TEXT NOT NULL); COMMIT;")
            if Int(version) ?? 0 < 2 {
                // Old snapshot remains authoritative until the entire migration commits.
                if let json = try scalar("SELECT payload FROM account_state LIMIT 1") {
                    let old = try JSONDecoder().decode(AccountState.self,from:Data(json.utf8))
                    _ = try save(old,replacing:true)
                } else { try exec("PRAGMA user_version=2") }
            }
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TradeError.corrupt("SQLite 交易失敗（\(sqlite3_errcode(db))）；未套用本次變更") }
    }
    private func scalar(_ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw TradeError.corrupt("SQLite 查詢失敗") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
    private func insert(_ sql: String, _ values: [String]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw TradeError.corrupt("SQLite 寫入準備失敗") }
        defer { sqlite3_finalize(stmt) }
        for (i, value) in values.enumerated() {
            let rc = value.withCString { sqlite3_bind_text(stmt, Int32(i + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard rc == SQLITE_OK else { throw TradeError.corrupt("SQLite 參數寫入失敗") }
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw TradeError.corrupt("事件或成交鍵衝突，交易已回滾") }
    }
    public func load() throws -> AccountState? {
        lock.lock(); defer { lock.unlock() }
        guard let json = try scalar("SELECT payload FROM account_state LIMIT 1") else { return nil }
        let state = try JSONDecoder().decode(AccountState.self, from: Data(json.utf8))
        if let h=state.history {
            guard h.fills>=0,h.ledger>=0,h.events>=0,
                  Int(try scalar("SELECT count(*) FROM fills") ?? "-1")==h.fills+state.fills.count,
                  Int(try scalar("SELECT count(*) FROM ledger") ?? "-1")==h.ledger+state.ledger.count,
                  Int(try scalar("SELECT count(*) FROM events") ?? "-1")==h.events+state.events.count else {throw TradeError.corrupt("歷史檢查點與資料表不符，保留原資料")}
        }
        try Self.validate(state, mode: mode)
        return state
    }
    public func fillPage(limit: Int = 100,before cursor: Int64? = nil,instrumentID:String? = nil) throws -> [FillPageRow] {
        guard (1...500).contains(limit),cursor == nil || cursor!>0 else{throw TradeError.invalid("歷史分頁參數不合法")}
        lock.lock();defer{lock.unlock()}
        let sql="SELECT rowid,payload FROM fills WHERE rowid < ? \(instrumentID == nil ? "":"AND json_extract(payload,'$.instrumentID')=?") ORDER BY rowid DESC LIMIT ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("無法查詢成交歷史")}
        defer{sqlite3_finalize(statement)}
        sqlite3_bind_int64(statement,1,cursor ?? Int64.max)
        if let instrumentID{_=instrumentID.withCString{sqlite3_bind_text(statement,2,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))};sqlite3_bind_int(statement,3,Int32(limit))}else{sqlite3_bind_int(statement,2,Int32(limit))}
        var rows:[FillPageRow]=[]
        var status=sqlite3_step(statement)
        while status==SQLITE_ROW {
            guard let text=sqlite3_column_text(statement,1) else{throw TradeError.corrupt("成交歷史格式損壞")}
            let fill=try JSONDecoder().decode(Fill.self,from:Data(String(cString:text).utf8))
            guard fill.accountID==mode.accountID else{throw TradeError.wrongAccount}
            rows.append(FillPageRow(cursor:sqlite3_column_int64(statement,0),fill:fill));status=sqlite3_step(statement)
        }
        guard status==SQLITE_DONE else{throw TradeError.corrupt("成交分頁讀取中斷")}
        return rows
    }
    public static func encode<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(object)
    }
    public static func validate(_ state: AccountState, mode: Mode) throws {
        guard state.schema == 1, state.mode == mode, state.accountID == mode.accountID,
              state.orders.values.allSatisfy({ $0.accountID == mode.accountID }),
              state.fills.allSatisfy({ $0.accountID == mode.accountID }),
              state.ledger.allSatisfy({ $0.accountID == mode.accountID }) else { throw TradeError.wrongAccount }
        if mode == .offline {
            guard let simulation=state.simulation,simulation.algorithm=="factor-wave-1",simulation.time%Simulation.step==0,state.instruments.allSatisfy({$0.id.hasPrefix("SIM:") && $0.initialPrice > .zero}) else{throw TradeError.corrupt("離線市場版本、時鐘或商品邊界不合法")}
        }else{guard state.simulation == nil,!state.instruments.contains(where:{$0.id.hasPrefix("SIM:")}) else{throw TradeError.wrongAccount}}
        guard !state.instruments.isEmpty,Set(state.instruments.map(\.id)).count==state.instruments.count,
              state.instruments.allSatisfy({i in
                  !i.id.isEmpty && i.rules.tick > .zero && i.rules.quantityStep > .zero && i.rules.multiplier > .zero && i.rules.maintenance >= .zero && i.rules.maxLeverage>=1 && TimeZone(identifier:i.rules.timeZone) != nil && i.rules.fees.maker >= .zero && i.rules.fees.taker >= .zero && i.rules.fees.minimum >= .zero && i.rules.fees.fixed >= .zero && i.rules.fees.sellTax >= .zero
              }) else{throw TradeError.corrupt("商品目錄或規則結構不合法，保留原始帳戶")}
        let instrumentIDs=Set(state.instruments.map(\.id))
        guard state.positions.allSatisfy({key,p in key==p.id && instrumentIDs.contains(p.id) && p.average >= .zero && p.margin >= .zero}),
              state.fills.allSatisfy({$0.quantity > .zero && $0.price > .zero && $0.fee >= .zero && $0.tax >= .zero && state.orders[$0.orderID] != nil && instrumentIDs.contains($0.instrumentID)}) else{throw TradeError.corrupt("部位或成交結構不合法")}
        let groups = Dictionary(grouping: state.ledger, by: { "\($0.eventID)|\($0.currency)" })
        for entries in groups.values where try sum(entries.map(\.amount)) != .zero { throw TradeError.corrupt("帳本不平衡，拒絕載入或寫入") }
        for currency in Set(state.cash.keys).union(state.ledger.map(\.currency)) {
            let rebuilt=try (state.history?.cashBefore[currency] ?? .zero) + sum(state.ledger.filter{$0.currency==currency && $0.account=="cash"}.map(\.amount))
            guard rebuilt == (state.cash[currency] ?? .zero) else {throw TradeError.corrupt("現金投影與帳本不符，保留原始資料")}
        }
        for (id,o) in state.orders {
            let r=o.request
            guard id==o.id,r.requestID==o.id,instrumentIDs.contains(r.instrumentID),r.quantity > .zero,o.filled >= .zero,o.filled <= r.quantity,o.reserved >= .zero,o.referencePrice > .zero,r.leverage>=1 else {throw TradeError.corrupt("委託數量、識別或保留不符")}
            if [.limit,.stopLimit].contains(r.kind){guard let price=r.price,price > .zero else{throw TradeError.corrupt("限價委託缺少有效價格")}}
            if r.kind.conditional && r.kind != .trailing{guard let trigger=r.trigger,trigger > .zero else{throw TradeError.corrupt("條件委託缺少有效觸發價")}}
            if r.kind == .trailing{guard (r.trailingDistance ?? .zero) > .zero else{throw TradeError.corrupt("移動停損距離不合法")}}
            if r.postOnly{guard r.kind == .limit,r.price != nil else{throw TradeError.corrupt("Post-only 結構不合法")}}
        }
        guard Set(state.fills.map(\.id)).count == state.fills.count, Set(state.events.map(\.id)).count == state.events.count else { throw TradeError.corrupt("重複事件或成交") }
    }
    /// Prepared once per batch. A duplicate immutable key must contain exactly the same payload.
    private func batch(_ sql: String, rows: [[String]], immutableTable: String? = nil, key: String = "id") throws {
        guard !rows.isEmpty else{return}
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK else{throw TradeError.corrupt("歷史寫入準備失敗")}
        defer{sqlite3_finalize(stmt)}
        for row in rows {
            sqlite3_reset(stmt);sqlite3_clear_bindings(stmt)
            for (n,value) in row.enumerated(){
                let rc=value.withCString{sqlite3_bind_text(stmt,Int32(n+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
                guard rc==SQLITE_OK else{throw TradeError.corrupt("歷史參數寫入失敗")}
            }
            guard sqlite3_step(stmt)==SQLITE_DONE else{throw TradeError.corrupt("歷史唯一鍵衝突，已回滾")}
            if let table=immutableTable,sqlite3_changes(db)==0 {
                var check:OpaquePointer?
                guard sqlite3_prepare_v2(db,"SELECT payload FROM \(table) WHERE \(key)=?",-1,&check,nil)==SQLITE_OK else{throw TradeError.corrupt("重複事件查核失敗")}
                defer{sqlite3_finalize(check)}
                _=row[0].withCString{sqlite3_bind_text(check,1,$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
                guard sqlite3_step(check)==SQLITE_ROW,let text=sqlite3_column_text(check,0),String(cString:text)==row.last! else{throw TradeError.corrupt("同一事件識別的內容不符，已回滾")}
            }
        }
    }
    private static let window = 100
    private static func compact(_ state: AccountState) throws -> AccountState {
        var s=state,h=s.history ?? HistoryWindow()
        let fillDrop=max(0,s.fills.count-window),eventDrop=max(0,s.events.count-window)
        var totals=h.totals ?? [:]
        let currencies=Dictionary(uniqueKeysWithValues:s.instruments.map{($0.id,$0.currency)})
        for fill in s.fills.prefix(fillDrop){let currency=currencies[fill.instrumentID]!;var total=totals[currency] ?? FillTotals();try total.include(fill);totals[currency]=total}
        h.totals=totals
        // Entries are balanced pairs. Never cut an event/currency group in half.
        var ledgerDrop=max(0,s.ledger.count-window)
        while ledgerDrop>0 && ledgerDrop<s.ledger.count && s.ledger[ledgerDrop-1].eventID==s.ledger[ledgerDrop].eventID{ledgerDrop-=1}
        for entry in s.ledger.prefix(ledgerDrop) where entry.account=="cash"{h.cashBefore[entry.currency]=try (h.cashBefore[entry.currency] ?? .zero)+entry.amount}
        h.fills+=fillDrop;h.events+=eventDrop;h.ledger+=ledgerDrop
        s.fills=Array(s.fills.dropFirst(fillDrop));s.events=Array(s.events.dropFirst(eventDrop));s.ledger=Array(s.ledger.dropFirst(ledgerDrop));s.history=h
        var keep=Set(s.orders.values.filter{$0.status.open}.map(\.id))
        keep.formUnion(s.orders.values.sorted{($0.updatedAt,$0.id)>($1.updatedAt,$1.id)}.prefix(window).map(\.id))
        keep.formUnion(s.fills.map(\.orderID))
        // Keep protection parents/children while any child is active.
        for order in s.orders.values where order.status.open{if let parent=order.request.parentID{keep.insert(parent)}}
        s.orders=s.orders.filter{keep.contains($0.key)}
        return s
    }
    @discardableResult public func save(_ state: AccountState, replacing: Bool = false) throws -> AccountState {
        lock.lock(); defer { lock.unlock() }
        if replacing && (state.history.map{$0.fills>0 || $0.ledger>0 || $0.events>0} ?? false){throw TradeError.corrupt("完整還原不可使用分頁投影")}
        try Self.validate(state, mode: mode)
        let compact=try Self.compact(state)
        func json<T:Encodable>(_ x:T)throws->String{String(decoding:try Self.encode(x),as:UTF8.self)}
        try exec("BEGIN IMMEDIATE")
        do {
            if replacing { try exec("DELETE FROM fill_report; DELETE FROM events; DELETE FROM fills; DELETE FROM orders; DELETE FROM ledger;") }
            try batch("INSERT OR IGNORE INTO events(id,account_id,sequence,payload) VALUES(?,?,?,?)",rows:try state.events.map{[$0.id,state.accountID,String($0.sequence),try json($0)]},immutableTable:"events")
            try batch("INSERT OR IGNORE INTO fills(id,order_id,account_id,time,payload) VALUES(?,?,?,?,?)",rows:try state.fills.map{[$0.id,$0.orderID,state.accountID,String($0.time),try json($0)]},immutableTable:"fills")
            try batch("INSERT OR IGNORE INTO fill_report(id,cells) VALUES(?,?)",rows:state.fills.map{[$0.id,Analytics.fillFields($0).map(Analytics.csvCell).joined(separator:",")]})
            try batch("INSERT OR IGNORE INTO ledger(ordinal,account_id,payload) VALUES(?,?,?)",rows:try state.ledger.enumerated().map{[String((state.history?.ledger ?? 0)+$0.offset+1),state.accountID,try json($0.element)]},immutableTable:"ledger",key:"ordinal")
            try batch("INSERT INTO orders(id,account_id,time,instrument,status,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,payload=excluded.payload,time=excluded.time",rows:try state.orders.values.map{[$0.id,state.accountID,String($0.updatedAt),$0.request.instrumentID,$0.status.rawValue,try json($0)]})
            try insert("INSERT INTO account_state(account_id,payload) VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload", [state.accountID,try json(compact)])
            try exec("PRAGMA user_version=2; COMMIT")
            return compact
        } catch { try? exec("ROLLBACK"); throw error }
    }
    private func readRows<T:Decodable>(_ type:T.Type,sql:String,values:[String]=[])throws->[T]{
        var rows:[T]=[]
        try visit(sql,values:values){rows.append(try JSONDecoder().decode(T.self,from:Data($0.utf8)))}
        return rows
    }
    private func visit(_ sql:String,values:[String]=[],body:(String)throws->Void)throws{
        var stmt:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK else{throw TradeError.corrupt("歷史查詢準備失敗")}
        defer{sqlite3_finalize(stmt)}
        for (n,value) in values.enumerated(){_=value.withCString{sqlite3_bind_text(stmt,Int32(n+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}}
        var status=sqlite3_step(stmt)
        while status==SQLITE_ROW{guard let text=sqlite3_column_text(stmt,0) else{throw TradeError.corrupt("歷史資料損壞")};try body(String(cString:text));status=sqlite3_step(stmt)}
        guard status==SQLITE_DONE else{throw TradeError.corrupt("歷史查詢中斷")}
    }
    /// Explicit full-history operation for backup/integrity checks, never used to render a screen.
    public func fullSnapshot()throws->AccountState?{
        lock.lock();defer{lock.unlock()}
        guard let json=try scalar("SELECT payload FROM account_state LIMIT 1") else{return nil}
        var s=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8))
        s.orders=Dictionary(uniqueKeysWithValues:try readRows(Order.self,sql:"SELECT payload FROM orders").map{($0.id,$0)})
        s.fills=try readRows(Fill.self,sql:"SELECT payload FROM fills ORDER BY rowid")
        s.events=try readRows(AuditEvent.self,sql:"SELECT payload FROM events ORDER BY sequence")
        s.ledger=try readRows(LedgerEntry.self,sql:"SELECT payload FROM ledger ORDER BY ordinal")
        s.history=nil;try Self.validate(s,mode:mode);return s
    }
    public func order(id:String)throws->Order?{
        lock.lock();defer{lock.unlock()}
        return try readRows(Order.self,sql:"SELECT payload FROM orders WHERE id=?",values:[id]).first
    }
    public func orderPage(limit:Int=100,before time:Int64?=nil,beforeID:String?=nil,search:String="")throws->[Order]{
        guard (1...100).contains(limit),search.utf8.count<=100 else{throw TradeError.invalid("委託查詢超過範圍")}
        lock.lock();defer{lock.unlock()}
        return try readRows(Order.self,sql:"SELECT payload FROM orders WHERE (time < ? OR (time = ? AND id < ?)) AND instr(instrument,?)>0 ORDER BY time DESC,id DESC LIMIT ?",values:[String(time ?? Int64.max),String(time ?? Int64.max),beforeID ?? "\u{10FFFF}",search,String(limit)])
    }
    public func csv(kind:String,time:Int64)throws->Data{
        lock.lock();defer{lock.unlock()}
        guard let json=try scalar("SELECT payload FROM account_state LIMIT 1") else{throw TradeError.corrupt("帳戶不存在")}
        let s=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8))
        var output=Data()
        func write(_ row:[String]){if !output.isEmpty{output.append(contentsOf:[13,10])};output.append(contentsOf:row.map(Analytics.csvCell).joined(separator:",").utf8)}
        let decoder=JSONDecoder()
        switch kind{
        case "fills":
            write(Analytics.fillHeader)
            let prefix=["模擬交易",s.accountID,s.mode.rawValue,String(s.schema),String(time)].map(Analytics.csvCell).joined(separator:",")+","
            guard try scalar("SELECT count(*) FROM fill_report")==scalar("SELECT count(*) FROM fills") else{throw TradeError.corrupt("成交報表索引不完整，匯出中止")}
            try visit("SELECT r.cells FROM fills f JOIN fill_report r ON r.id=f.id ORDER BY f.rowid"){output.append(contentsOf:[13,10]);output.append(contentsOf:prefix.utf8);output.append(contentsOf:$0.utf8)}
        case "ledger":
            write(["模擬交易","accountID","exportedAt","eventID","time","currency","account","amount"])
            try visit("SELECT payload FROM ledger ORDER BY ordinal"){let e=try decoder.decode(LedgerEntry.self,from:Data($0.utf8));write(["模擬交易",s.accountID,String(time),e.eventID,String(e.time),e.currency,e.account,e.amount.description])}
        case "orders":
            write(Analytics.orderHeader)
            try visit("SELECT payload FROM orders ORDER BY time,id"){let o=try decoder.decode(Order.self,from:Data($0.utf8));write(Analytics.orderRow(o,account:s,time:time))}
        default:throw TradeError.invalid("未知匯出類型")
        }
        return output
    }

}

public struct AppSettings: Codable, Sendable {
    public var activeMode: Mode = .offline
    public var pendingMode: Mode?
    public var onboarded = false
    public var theme = "dark"
    public var taiwanColors = true
    public var hideBalances = false
    public init() {}
    public static func load(root: URL) throws -> Self {
        let url = root.appendingPathComponent("app-settings.json")
        if !FileManager.default.fileExists(atPath: url.path) { return Self() }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    public func save(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try AccountRepository.encode(self).write(to: root.appendingPathComponent("app-settings.json"), options: .atomic)
    }
}
