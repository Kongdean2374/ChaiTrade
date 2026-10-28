import Foundation
import CSQLite

public struct FillPageRow: Sendable,Identifiable {
    public let cursor: Int64
    public let fill: Fill
    public var id: String{fill.id}
}

/// Serial access is owned by TradingEngine. SQLite transactions protect the snapshot and idempotency indices.
public final class AccountRepository: @unchecked Sendable {
    var db: OpaquePointer?
    let lock = NSLock()
    private var cachedEquity:[EquityPoint]=[]
    private var cachedEquityOffset=0
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
            guard Int(version) ?? 99 <= 9 else { throw TradeError.corrupt("資料庫版本較新，請更新 App；不可降版覆寫") }
            try exec("BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS account_state (account_id TEXT PRIMARY KEY, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, sequence INTEGER NOT NULL UNIQUE, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS fills (id TEXT PRIMARY KEY, order_id TEXT NOT NULL, account_id TEXT NOT NULL, time INTEGER NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS fills_time ON fills(time); CREATE INDEX IF NOT EXISTS fills_order ON fills(order_id); CREATE INDEX IF NOT EXISTS fills_instrument_time ON fills(account_id,time); CREATE TABLE IF NOT EXISTS equity (ordinal INTEGER PRIMARY KEY,account_id TEXT NOT NULL,metrics TEXT NOT NULL,payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS financial_flows (id TEXT PRIMARY KEY,account_id TEXT NOT NULL,time INTEGER NOT NULL,sequence INTEGER NOT NULL,payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS financial_flows_time ON financial_flows(time,sequence); CREATE TABLE IF NOT EXISTS report_state (id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS report_checkpoints (time INTEGER PRIMARY KEY,payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS fill_report (id TEXT PRIMARY KEY REFERENCES fills(id), cells TEXT NOT NULL); CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, time INTEGER NOT NULL, instrument TEXT NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS orders_time ON orders(time); CREATE INDEX IF NOT EXISTS orders_time_id ON orders(time DESC,id DESC); CREATE INDEX IF NOT EXISTS fills_instrument ON fills(json_extract(payload,'$.instrumentID')); CREATE INDEX IF NOT EXISTS fills_simulation_history ON fills(json_extract(payload,'$.instrumentID'),time); CREATE TABLE IF NOT EXISTS ledger (ordinal INTEGER PRIMARY KEY, account_id TEXT NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS ledger_account_count ON ledger(account_id); CREATE INDEX IF NOT EXISTS equity_account_count ON equity(account_id); COMMIT;")
            try createJournalSchema();try createAppliedEventSchema();try createLifecycleSchema()
            if Int(version) ?? 0 < 5 {
                if let json=try scalar("SELECT payload FROM account_state LIMIT 1"){
                    var old=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8)),full=old
                    if (old.history?.fills ?? 0)>0{full.orders=Dictionary(uniqueKeysWithValues:try readRows(Order.self,sql:"SELECT payload FROM orders").map{($0.id,$0)});full.fills=try readRows(Fill.self,sql:"SELECT payload FROM fills ORDER BY rowid")}
                    if (old.history?.events ?? 0)>0{full.events=try readRows(AuditEvent.self,sql:"SELECT payload FROM events ORDER BY sequence")}
                    if (old.history?.ledger ?? 0)>0{full.ledger=try readRows(LedgerEntry.self,sql:"SELECT payload FROM ledger ORDER BY ordinal")}
                    if old.history?.lifecycleCounts != nil{full.lifecycle=try lifecycleProjectionUnlocked(old.lifecycle,full:true)}
                    old.financialFlows=try FinancialFlowMigration.reconstruct(full)
                    if old.history != nil{old.history!.financialFlowOffset=0}
                    _=try save(old,replacing:(Int(version) ?? 0)<2)
                }else{try exec("PRAGMA user_version=6")}
            }
            if version=="5"{
                if let json=try scalar("SELECT payload FROM account_state LIMIT 1"){_=try save(JSONDecoder().decode(AccountState.self,from:Data(json.utf8)))}else{try exec("PRAGMA user_version=6")}
            }
            if (Int(version) ?? 0)<7{
                if let json=try scalar("SELECT payload FROM account_state LIMIT 1"){_=try save(JSONDecoder().decode(AccountState.self,from:Data(json.utf8)))}else{try exec("PRAGMA user_version=7")}
            }
            if (Int(version) ?? 0)<8{
                if let json=try scalar("SELECT payload FROM account_state LIMIT 1"){_=try save(JSONDecoder().decode(AccountState.self,from:Data(json.utf8)))}else{try exec("PRAGMA user_version=8")}
            }
            if (Int(version) ?? 0)<9{
                if let json=try scalar("SELECT payload FROM account_state LIMIT 1"){_=try save(JSONDecoder().decode(AccountState.self,from:Data(json.utf8)))}else{try exec("PRAGMA user_version=9")}
            }
            try exec("CREATE INDEX IF NOT EXISTS fills_with_simulation_impact ON fills(json_extract(payload,'$.instrumentID'),time) WHERE json_extract(payload,'$.simulationImpact') IS NOT NULL")
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private init(reading path:String,mode:Mode)throws{
        self.path=path;self.mode=mode
        guard sqlite3_open_v2(path,&db,SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else{throw TradeError.corrupt("無法開啟一致性唯讀快照")}
        do{try exec("PRAGMA query_only=ON; PRAGMA busy_timeout=5000")}catch{sqlite3_close(db);db=nil;throw error}
    }
    static func archiveReader(_ url:URL,mode:Mode)throws->AccountRepository{try AccountRepository(reading:url.path,mode:mode)}
    func withArchiveConnection<T>(_ body:(OpaquePointer)throws->T)throws->T{lock.lock();defer{lock.unlock()};guard let db else{throw TradeError.corrupt("帳戶資料庫已關閉")};return try body(db)}
    func verifyCapitalHistory(_ state:AccountState)throws{lock.lock();defer{lock.unlock()};guard try reconstructCapitalBasis(state)==state.capitalBasis else{throw TradeError.corrupt("歸檔的歷史投入成本不符")}}
    func rebuildArchiveReports(_ state:AccountState)throws{
        lock.lock();defer{lock.unlock()};try exec("BEGIN IMMEDIATE")
        do{
            try exec("DELETE FROM report_state; DELETE FROM report_checkpoints; DELETE FROM fill_report")
            var rows:[[String]]=[]
            try visit("SELECT payload FROM fills ORDER BY rowid"){text in let fill=try JSONDecoder().decode(Fill.self,from:Data(text.utf8));rows.append([fill.id,Analytics.fillFields(fill).map(Analytics.csvCell).joined(separator:",")]);if rows.count==1000{try batch("INSERT INTO fill_report(id,cells) VALUES(?,?)",rows:rows);rows=[]}}
            try batch("INSERT INTO fill_report(id,cells) VALUES(?,?)",rows:rows);try updatePerformance(state,replacing:true);try exec("COMMIT")
        }catch{try? exec("ROLLBACK");throw error}
    }
    func createArchiveSnapshot(at url:URL)throws{
        guard !FileManager.default.fileExists(atPath:url.path) else{throw TradeError.invalid("快照目的地已存在，不覆蓋原檔")}
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        var target:OpaquePointer?;guard sqlite3_open_v2(url.path,&target,SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let target else{throw TradeError.unavailable("無法建立帳戶檔案快照")}
        var closed=false;defer{if !closed{sqlite3_close(target)}}
        do{
            try withArchiveConnection{source in try SQLiteArchiveDatabase.copy(source:source,target:target)}
            // This connection owns the snapshot, never the live account. A portable archive
            // must not depend on WAL/shm sidecars that a read-only platform cannot create.
            guard try SQLiteArchiveDatabase.strings(target,"PRAGMA journal_mode=DELETE")==["delete"] else{throw TradeError.unavailable("無法完成獨立帳戶快照；原帳戶保留")}
            guard sqlite3_close(target)==SQLITE_OK else{throw TradeError.unavailable("無法關閉獨立帳戶快照")}
            closed=true
            // Apple's VFS can leave the obsolete shared-memory index after switching
            // this exclusive, newly created snapshot to rollback mode. No reader has
            // received its URL yet; remove only that abandoned index after close.
            let shm=URL(fileURLWithPath:url.path+"-shm")
            if FileManager.default.fileExists(atPath:shm.path){try FileManager.default.removeItem(at:shm)}
            guard !FileManager.default.fileExists(atPath:url.path+"-wal") else{throw TradeError.corrupt("獨立帳戶快照仍有未合併日誌；不交付不完整檔案")}

        }catch{try? FileManager.default.removeItem(at:url);throw error}
    }
    func installArchiveSnapshot(_ verified:VerifiedAccountDatabase)throws->AccountState{
        guard verified.mode==mode else{throw TradeError.wrongAccount}
        guard try ArchiveDigest.file(verified.url)==verified.digest else{throw TradeError.corrupt("已驗證的恢復檔案發生變更，原帳戶未變")}
        var source:OpaquePointer?;guard sqlite3_open_v2(verified.url.path,&source,SQLITE_OPEN_READONLY,nil)==SQLITE_OK,let source else{throw TradeError.corrupt("無法開啟已驗證的恢復檔案")};defer{sqlite3_close(source)}
        try withArchiveConnection{target in try SQLiteArchiveDatabase.copy(source:source,target:target);cachedEquity=[];cachedEquityOffset=0}
        guard let state=try load() else{throw TradeError.corrupt("已恢復檔案缺少帳戶")};return state
    }
    func prepareArchiveFile()throws{
        try withArchiveConnection{db in
            guard sqlite3_exec(db,"PRAGMA secure_delete=ON; VACUUM",nil,nil,nil)==SQLITE_OK else{throw TradeError.unavailable("檔案快照整理失敗；原帳戶保留")}
            guard sqlite3_wal_checkpoint_v2(db,"main",SQLITE_CHECKPOINT_TRUNCATE,nil,nil)==SQLITE_OK else{throw TradeError.unavailable("無法完成檔案快照，請稍後重試")}
            guard try SQLiteArchiveDatabase.strings(db,"PRAGMA journal_mode=DELETE")==["delete"] else{throw TradeError.unavailable("無法完成可攜式帳戶快照")}
        }
    }
    public func readSnapshot(maximumExpandedBytes:Int?=nil)throws->AccountState?{try AccountRepository(reading:path,mode:mode).fullSnapshot(maximumExpandedBytes:maximumExpandedBytes)}
    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TradeError.corrupt("SQLite 交易失敗（\(sqlite3_errcode(db))）；未套用本次變更") }
    }
    func scalar(_ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw TradeError.corrupt("SQLite 查詢失敗") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(statement, 0).map { String(cString: $0) }
    }
    func insert(_ sql: String, _ values: [String]) throws {
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
            guard h.fills>=0,h.ledger>=0,h.events>=0,(h.financialFlowOffset ?? 0)>=0,
                  Int(try scalar("SELECT count(*) FROM financial_flows") ?? "-1")==((h.financialFlowOffset ?? 0)+(state.financialFlows?.count ?? 0)),(h.equityOffset ?? 0)>=0,((h.equityOffset ?? 0)==0 || h.equityMetrics != nil),
                  Int(try scalar("SELECT count(*) FROM equity") ?? "-1")==(h.equityOffset ?? 0)+state.equity.count,
                  Int(try scalar("SELECT count(*) FROM fills") ?? "-1")==h.fills+state.fills.count,
                  Int(try scalar("SELECT count(*) FROM ledger") ?? "-1")==h.ledger+state.ledger.count,
                  Int(try scalar("SELECT count(*) FROM events") ?? "-1")==h.events+state.events.count else {throw TradeError.corrupt("歷史檢查點與資料表不符，保留原資料")}
        }
        if let count=state.history?.journalCount{guard try journalCountUnlocked()==count else{throw TradeError.corrupt("日誌歷史檢查點不符，原資料保留")}}
        if let count=state.history?.appliedEventCount{guard try appliedEventCountUnlocked()==count else{throw TradeError.corrupt("冪等事件歷史檢查點不符，原資料保留")}}
        if let counts=state.history?.lifecycleCounts{guard try lifecycleCountsUnlocked()==counts else{throw TradeError.corrupt("帳務歷史檢查點不符，原資料保留")}}
        try Self.validate(state, mode: mode)
        cachedEquity=state.equity;cachedEquityOffset=state.history?.equityOffset ?? 0
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
    public func equityPage(limit:Int=100,before cursor:Int64?=nil)throws->[EquityPageRow]{
        guard (1...500).contains(limit),cursor==nil || cursor!>0 else{throw TradeError.invalid("估值分頁參數不合法")}
        lock.lock();defer{lock.unlock()}
        var statement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT ordinal,payload,metrics FROM equity WHERE ordinal<? ORDER BY ordinal DESC LIMIT ?",-1,&statement,nil)==SQLITE_OK else{throw TradeError.corrupt("無法查詢估值歷史")}
        defer{sqlite3_finalize(statement)}
        sqlite3_bind_int64(statement,1,cursor ?? Int64.max);sqlite3_bind_int(statement,2,Int32(limit))
        var rows:[EquityPageRow]=[],status=sqlite3_step(statement)
        let decoder=JSONDecoder()
        while status==SQLITE_ROW{
            guard let p=sqlite3_column_text(statement,1),let m=sqlite3_column_text(statement,2) else{throw TradeError.corrupt("估值資料損壞")}
            rows.append(EquityPageRow(cursor:sqlite3_column_int64(statement,0),point:try decoder.decode(EquityPoint.self,from:Data(String(cString:p).utf8)),metrics:try decoder.decode(EquityMetrics.self,from:Data(String(cString:m).utf8))))
            status=sqlite3_step(statement)
        }
        guard status==SQLITE_DONE else{throw TradeError.corrupt("估值查詢中斷")};return rows
    }
    public static func encode<T: Encodable>(_ object: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(object)
    }
    public static func validate(_ state: AccountState, mode: Mode) throws {
        try state.productPreferences?.tradeWorkspace?.validate(in:state)
        if let basis=state.capitalBasis{
            guard basis.matches(state.netFlows),basis.unvaluedCount>=basis.unvaluedCurrencies.count,basis.unvaluedCount>=0 else{throw TradeError.corrupt("歷史投入成本與外部資金不符")}
            if (state.history?.ledger ?? 0)==0{guard try basis==CapitalBasis.reconstruct(state) else{throw TradeError.corrupt("歷史投入成本與原始帳本／匯率證據不符")}}
        }
        for instrument in state.instruments{try TradingSessions.validate(instrument.rules)}
        guard (1...2).contains(state.schema), state.mode == mode, state.accountID == mode.accountID,
              state.orders.values.allSatisfy({ $0.accountID == mode.accountID }),
              state.fills.allSatisfy({ $0.accountID == mode.accountID }),
              state.ledger.allSatisfy({ $0.accountID == mode.accountID }) else { throw TradeError.wrongAccount }
        if mode == .offline {
            if let universe=state.simulation?.newsUniverse,let worldID=state.simulation?.newsWorldID{
                guard Set(universe.map(\.id)).count==universe.count,worldID==BackupService.digest(try encode(universe)) else{throw TradeError.corrupt("模擬新聞世界身份與商品資料不符，保留原始資料")}
            }
            if let simulation=state.simulation,simulation.algorithm=="factor-wave-3"{
                guard ["factor-wave-1","factor-wave-2"].contains(simulation.baseAlgorithm ?? ""),let enabled=simulation.participantsFrom,enabled>=0,enabled<=32_503_680_000,enabled%Simulation.step==0 else{throw TradeError.corrupt("離線參與者版本或生效時間不合法")}
                let known=Set(state.instruments.map(\.id)),groups=simulation.impactGroups ?? []
                guard Set(groups.map(\.groupID)).count==groups.count,zip(groups,groups.dropFirst()).allSatisfy({($0.volumeTime,$0.groupID)<($1.volumeTime,$1.groupID)}),groups.allSatisfy({known.contains($0.instrumentID) && $0.volumeTime>=enabled && $0.volumeTime<=simulation.time && $0.volumeTime%Simulation.step==0 && $0.startsAt==$0.volumeTime+Simulation.step && $0.endsAt==$0.startsAt+300 && $0.volume >= .zero && $0.amplitude.magnitude <= Amount.max}) else{throw TradeError.corrupt("交易衝擊時間線或商品身份不合法")}
                guard (state.participantUsage ?? [:]).values.allSatisfy({$0.quantity >= .zero && $0.expiresAt>simulation.time && $0.expiresAt<=simulation.time+60}) else{throw TradeError.corrupt("模擬流動性池用量或期限不合法")}
            }
            guard let simulation=state.simulation,["factor-wave-1","factor-wave-2","factor-wave-3"].contains(simulation.algorithm),simulation.time>=0,simulation.time<=32_503_680_000,simulation.time%Simulation.step==0,simulation.changes.allSatisfy({$0.time>=0 && $0.time<=simulation.time+Simulation.step && $0.time%Simulation.step==0 && $0.volatility.isFinite && (0.1...5).contains($0.volatility) && $0.liquidity.isFinite && (0.1...10).contains($0.liquidity) && ["多頭","空頭","盤整","恐慌","復甦"].contains($0.scenario)}),zip(simulation.changes,simulation.changes.dropFirst()).allSatisfy({$0.0.time<=$0.1.time}),state.instruments.allSatisfy({$0.id.hasPrefix("SIM:") && $0.initialPrice > .zero}) else{throw TradeError.corrupt("離線市場版本、時鐘或商品邊界不合法")}
        }else{guard state.simulation == nil,!state.instruments.contains(where:{$0.id.hasPrefix("SIM:")}) else{throw TradeError.wrongAccount}}
        guard !state.instruments.isEmpty,Set(state.instruments.map(\.id)).count==state.instruments.count,
              state.instruments.allSatisfy({i in
                  !i.id.isEmpty && i.rules.tick > .zero && i.rules.quantityStep > .zero && i.rules.multiplier > .zero && i.rules.maintenance >= .zero && i.rules.maxLeverage>=1 && (i.rules.expiry == nil || i.rules.expiry!>=0) && TimeZone(identifier:i.rules.timeZone) != nil && i.rules.fees.maker >= .zero && i.rules.fees.taker >= .zero && i.rules.fees.minimum >= .zero && i.rules.fees.fixed >= .zero && i.rules.fees.sellTax >= .zero
              }) else{throw TradeError.corrupt("商品目錄或規則結構不合法，保留原始帳戶")}
        for i in state.instruments{
            try i.rules.validateRiskTiers()
            if let schedule=i.rules.carrySchedule{
                guard state.schema>=2,i.asset.derivative,(5...604800).contains(schedule.interval),schedule.interval%5==0,schedule.offset>=0,schedule.offset<schedule.interval,schedule.offset%5==0,schedule.longRate.magnitude <= .one,schedule.shortRate.magnitude <= .one,["funding","interest"].contains(schedule.kind) else{throw TradeError.corrupt("持有費排程不合法")}
            }
            if let minute=i.rules.dailySettlementMinute{guard state.schema>=2,i.asset == .future,(0..<1440).contains(minute) else{throw TradeError.corrupt("每日結算排程不合法")}}
        }
        let instrumentIDs=Set(state.instruments.map(\.id))
        guard Set(state.alerts.map(\.id)).count==state.alerts.count else{throw TradeError.corrupt("價格提醒身份重複")}
        for alert in state.alerts{
            guard instrumentIDs.contains(alert.instrumentID),alert.price > .zero,!alert.id.isEmpty,alert.id.count<=128 else{throw TradeError.corrupt("價格提醒商品、價格或身份不合法")}
            if let percentage=alert.percentage{
                let hundred=try Amount(100),maximum=try Amount(1000)
                guard percentage > .zero,percentage<=maximum,alert.above || percentage<hundred,let baseline=alert.baseline,baseline > .zero,let time=alert.baselineTime,time>=0,alert.basis != nil else{throw TradeError.corrupt("百分比提醒缺少固定基準")}
                let ratio=try percentage/hundred,threshold=try baseline*(alert.above ? .one+ratio:.one-ratio)
                guard alert.price==threshold else{throw TradeError.corrupt("百分比提醒觸發價與固定基準不符")}
            }else{guard alert.baseline==nil,alert.baselineTime==nil,alert.basis==nil else{throw TradeError.corrupt("絕對價格提醒不應有百分比基準")}}
        }
        guard state.marginWarningLevels?.allSatisfy({state.positions[$0.key] != nil && (0...2).contains($0.value)}) ?? true else{throw TradeError.corrupt("保證金提醒狀態不合法")}
        guard state.financialFlows?.allSatisfy({$0.accountID==state.accountID && instrumentIDs.contains($0.instrumentID) && $0.time>=0 && $0.sequence>=0 && ($0.quantityRatio==nil || $0.quantityRatio! > .zero)}) ?? true else{throw TradeError.corrupt("績效現金流帳戶、商品或數量比例不符")}

        guard state.chartPreferences?.allSatisfy({id,p in instrumentIDs.contains(id) && (2...100).contains(p.period) && [60,300,900,1800,3600,14400,86400,604800,2592000].contains(p.interval) && ["無","MA","EMA","MACD","RSI","KD","BOLL","VWAP","ATR"].contains(p.indicator)}) ?? true else{throw TradeError.corrupt("圖表偏好不合法")}
        guard state.inbox?.allSatisfy({$0.accountID==state.accountID && $0.id=="\(state.accountID).\($0.event.id)"}) ?? true else{throw TradeError.wrongAccount}
        guard Set(state.journals.map(\.id)).count==state.journals.count else{throw TradeError.corrupt("日誌識別重複")}
        for j in state.journals{try Self.validateJournal(j,instrumentIDs:instrumentIDs,allowProjection:state.history?.journalCount != nil)}
        try Self.validateLifecycle(state.lifecycle,instrumentIDs:instrumentIDs)
        guard state.positions.allSatisfy({key,p in key==p.id && instrumentIDs.contains(p.instrumentKey) && p.average >= .zero && p.margin >= .zero}),
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
    func batch(_ sql: String, rows: [[String]], immutableTable: String? = nil, key: String = "id") throws {
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
        if s.simulation != nil{
            let time=s.simulation!.time,expired=(s.simulation!.impactGroups ?? []).filter{$0.endsAt+65<time}
            if let last=expired.map(\.endsAt).max(){s.simulation!.impactArchiveCutoff=max(s.simulation!.impactArchiveCutoff ?? 0,last)}
            s.simulation!.impactGroups=s.simulation!.impactGroups?.filter{$0.endsAt+65>=time}
        }
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
        let equityDrop=max(0,s.equity.count-1000)
        var metrics=h.equityMetrics ?? EquityMetrics()
        for point in s.equity.prefix(equityDrop){metrics.consume(point)}
        h.equityOffset=(h.equityOffset ?? 0)+equityDrop;h.equityMetrics=metrics
        let flowDrop=max(0,(s.financialFlows?.count ?? 0)-window)
        h.financialFlowOffset=(h.financialFlowOffset ?? 0)+flowDrop
        if s.financialFlows != nil{s.financialFlows=Array(s.financialFlows!.dropFirst(flowDrop))}
        s.equity=Array(s.equity.dropFirst(equityDrop))
        s.fills=Array(s.fills.dropFirst(fillDrop));s.events=Array(s.events.dropFirst(eventDrop));s.ledger=Array(s.ledger.dropFirst(ledgerDrop));s.history=h
        var keep=Set(s.orders.values.filter{$0.status.open}.map(\.id))
        keep.formUnion(s.orders.values.sorted{($0.updatedAt,$0.id)>($1.updatedAt,$1.id)}.prefix(window).map(\.id))
        keep.formUnion(s.fills.map(\.orderID))
        // Keep protection parents/children while any child is active.
        for order in s.orders.values where order.status.open{if let parent=order.request.parentID{keep.insert(parent)}}
        s.orders=s.orders.filter{keep.contains($0.key)}
        return s
    }
    private func reconstructCapitalBasis(_ state:AccountState)throws->CapitalBasis{
        if (state.history?.ledger ?? 0)==0{return try CapitalBasis.reconstruct(state)}
        struct Row:Decodable{var ledger:LedgerEntry;var flow:CapitalFlowValuation?}
        var basis=CapitalBasis(),seen=Set<String>()
        func include(_ entry:LedgerEntry,flow:CapitalFlowValuation?)throws{
            guard seen.insert(entry.eventID).inserted else{throw TradeError.corrupt("歷史外部資金身份重複")}
            try basis.include(try CapitalBasis.checkedFlow(entry:entry,metadata:flow,base:state.baseCurrency))
        }
        let sql="SELECT json_object('ledger',json(l.payload),'flow',json_extract(e.payload,'$.capitalFlow')) FROM ledger l LEFT JOIN events e ON e.id=json_extract(l.payload,'$.eventID') WHERE l.ordinal<=? AND json_extract(l.payload,'$.account')='external-capital' ORDER BY l.ordinal"
        try visit(sql,values:[String(state.history!.ledger)]){text in let row=try JSONDecoder().decode(Row.self,from:Data(text.utf8));try include(row.ledger,flow:row.flow)}
        for entry in state.ledger where entry.account=="external-capital"{
            let event=try state.events.first{$0.id==entry.eventID} ?? readRows(AuditEvent.self,sql:"SELECT payload FROM events WHERE id=? LIMIT 1",values:[entry.eventID]).first
            try include(entry,flow:event?.capitalFlow)
        }
        guard basis.matches(state.netFlows) else{throw TradeError.corrupt("外部資金歷史與淨投入不符")}
        return basis
    }
    @discardableResult public func save(_ proposed: AccountState, replacing: Bool = false) throws -> AccountState {
        #if CHAI_STORAGE_PROFILE
        var profile=WritePathProfile("repository.save")
        defer{profile.emit()}
        #endif
        lock.lock(); defer { lock.unlock() }
        #if CHAI_STORAGE_PROFILE
        profile.mark("lock")
        #endif
        var state=proposed
        if state.capitalBasis==nil{state.capitalBasis=try reconstructCapitalBasis(state)}
        let incompleteLifecycle=LifecycleHistoryKind.allCases.contains{kind in (state.history?.lifecycleCounts?[kind.rawValue] ?? 0)>Self.lifecycleRecords(state.lifecycle,kind:kind).count}
        if replacing && (incompleteLifecycle || (state.history.map{$0.fills>0 || $0.ledger>0 || $0.events>0 || ($0.equityOffset ?? 0)>0 || ($0.financialFlowOffset ?? 0)>0 || ($0.journalCount ?? proposed.journals.count)>proposed.journals.count || ($0.appliedEventCount ?? proposed.appliedEvents.count)>proposed.appliedEvents.count} ?? false)){throw TradeError.corrupt("完整還原不可使用分頁投影")}
        #if CHAI_STORAGE_PROFILE
        profile.mark("prepare")
        #endif
        try Self.validate(state, mode: mode)
            #if CHAI_STORAGE_PROFILE
            profile.mark("validate")
            #endif
        var compact=try Self.compact(state)
            #if CHAI_STORAGE_PROFILE
            profile.mark("compact")
            #endif
        let rebuildFillReport=(Int(try scalar("PRAGMA user_version") ?? "0") ?? 0)<5
        func json<T:Encodable>(_ x:T)throws->String{String(decoding:try Self.encode(x),as:UTF8.self)}
        try exec("BEGIN IMMEDIATE")
            #if CHAI_STORAGE_PROFILE
            profile.mark("begin")
            #endif
        do {
            if replacing { try exec("DELETE FROM lifecycle_history; DELETE FROM applied_event_ids; DELETE FROM journal_images; DELETE FROM journal_entries; DELETE FROM financial_flows; DELETE FROM equity; DELETE FROM report_state; DELETE FROM report_checkpoints; DELETE FROM fill_report; DELETE FROM events; DELETE FROM fills; DELETE FROM orders; DELETE FROM ledger;") }
            try batch("INSERT OR IGNORE INTO events(id,account_id,sequence,payload) VALUES(?,?,?,?)",rows:try state.events.map{[$0.id,state.accountID,String($0.sequence),try json($0)]},immutableTable:"events")
            #if CHAI_STORAGE_PROFILE
            profile.mark("events")
            #endif
            try batch("INSERT OR IGNORE INTO fills(id,order_id,account_id,time,payload) VALUES(?,?,?,?,?)",rows:try state.fills.map{[$0.id,$0.orderID,state.accountID,String($0.time),try json($0)]},immutableTable:"fills")
            #if CHAI_STORAGE_PROFILE
            profile.mark("fills")
            #endif
            try batch("INSERT OR IGNORE INTO financial_flows(id,account_id,time,sequence,payload) VALUES(?,?,?,?,?)",rows:try (state.financialFlows ?? []).map{[$0.id,state.accountID,String($0.time),String($0.sequence),try json($0)]},immutableTable:"financial_flows")
            #if CHAI_STORAGE_PROFILE
            profile.mark("flows")
            #endif
            guard Int(try scalar("SELECT count(*) FROM financial_flows") ?? "-1")==((state.history?.financialFlowOffset ?? 0)+(state.financialFlows?.count ?? 0)) else{throw TradeError.corrupt("績效現金流歷史來源已過期，交易已回滾")}
            try batch("INSERT OR IGNORE INTO fill_report(id,cells) VALUES(?,?)",rows:state.fills.map{[$0.id,Analytics.fillFields($0).map(Analytics.csvCell).joined(separator:",")]})
            #if CHAI_STORAGE_PROFILE
            profile.mark("fill_report")
            #endif
            try batch("INSERT OR IGNORE INTO ledger(ordinal,account_id,payload) VALUES(?,?,?)",rows:try state.ledger.enumerated().map{[String((state.history?.ledger ?? 0)+$0.offset+1),state.accountID,try json($0.element)]},immutableTable:"ledger",key:"ordinal")
            #if CHAI_STORAGE_PROFILE
            profile.mark("ledger")
            #endif
            // Preserve exact canonical rows while avoiding WAL/index writes for unchanged orders.
            try batch("INSERT INTO orders(id,account_id,time,instrument,status,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET status=excluded.status,payload=excluded.payload,time=excluded.time WHERE orders.status<>excluded.status OR orders.payload<>excluded.payload OR orders.time<>excluded.time",rows:try state.orders.values.map{[$0.id,state.accountID,String($0.updatedAt),$0.request.instrumentID,$0.status.rawValue,try json($0)]})
            #if CHAI_STORAGE_PROFILE
            profile.mark("orders")
            #endif
            guard Int(try scalar("SELECT count(*) FROM fills") ?? "-1")==((state.history?.fills ?? 0)+state.fills.count),Int(try scalar("SELECT count(*) FROM ledger") ?? "-1")==((state.history?.ledger ?? 0)+state.ledger.count),Int(try scalar("SELECT count(*) FROM events") ?? "-1")==((state.history?.events ?? 0)+state.events.count) else{throw TradeError.corrupt("寫入來源已過期或歷史筆數不符，已回滾")}
            #if CHAI_STORAGE_PROFILE
            profile.mark("exact_history_counts")
            #endif
            let offset=state.history?.equityOffset ?? 0,stored=Int(try scalar("SELECT coalesce(max(ordinal),0) FROM equity") ?? "0") ?? 0
            guard offset>=0,stored>=offset else{throw TradeError.corrupt("估值歷史檢查點不符")}
            let overlap=min(state.equity.count,stored-offset)
            if overlap>0{
                let expected:[EquityPoint]
                if !replacing,offset>=cachedEquityOffset,offset+overlap<=cachedEquityOffset+cachedEquity.count{expected=Array(cachedEquity[(offset-cachedEquityOffset)..<(offset-cachedEquityOffset+overlap)])}
                else{expected=try readRows(EquityPoint.self,sql:"SELECT payload FROM equity WHERE ordinal>? AND ordinal<=? ORDER BY ordinal",values:[String(offset),String(offset+overlap)])}
                guard state.equity.prefix(overlap).elementsEqual(expected) else{throw TradeError.corrupt("不可改寫已存在的估值事件")}
            }
            var metrics=state.history?.equityMetrics ?? EquityMetrics(),equityRows:[[String]]=[]
            if overlap>0{
                // The unchanged prefix was validated above. Resume its canonical persisted
                // metrics rather than recomputing all 1,000 hot points on every order.
                guard let checkpoint=try readRows(EquityMetrics.self,sql:"SELECT metrics FROM equity WHERE ordinal=?",values:[String(offset+overlap)]).first else{throw TradeError.corrupt("估值統計檢查點遺失")}
                metrics=checkpoint
            }
            for (n,point) in state.equity.enumerated().dropFirst(overlap){metrics.consume(point);let ordinal=offset+n+1;equityRows.append([String(ordinal),state.accountID,try json(metrics),try json(point)])}
            try batch("INSERT OR IGNORE INTO equity(ordinal,account_id,metrics,payload) VALUES(?,?,?,?)",rows:equityRows,immutableTable:"equity",key:"ordinal")
            guard Int(try scalar("SELECT count(*) FROM equity") ?? "-1")==offset+state.equity.count else{throw TradeError.corrupt("估值歷史來源已過期，已回滾")}
            #if CHAI_STORAGE_PROFILE
            profile.mark("equity")
            #endif
            if rebuildFillReport{
                try exec("DELETE FROM fill_report")
                var rows:[[String]]=[]
                try visit("SELECT payload FROM fills ORDER BY rowid"){text in let fill=try JSONDecoder().decode(Fill.self,from:Data(text.utf8));rows.append([fill.id,Analytics.fillFields(fill).map(Analytics.csvCell).joined(separator:",")]);if rows.count==1000{try batch("INSERT INTO fill_report(id,cells) VALUES(?,?)",rows:rows);rows=[]}}
                try batch("INSERT INTO fill_report(id,cells) VALUES(?,?)",rows:rows)
            }
            try saveAppliedEventsUnlocked(state,replacing:replacing)
            compact.appliedEvents=try appliedIDsUnlocked(limit:100)
            compact.history!.appliedEventCount=try appliedEventCountUnlocked()
            #if CHAI_STORAGE_PROFILE
            profile.mark("applied_events")
            #endif
            try saveJournalsUnlocked(state,replacing:replacing)
            compact.journals=try journalProjectionUnlocked(limit:20)
            compact.history!.journalCount=try journalCountUnlocked()
            #if CHAI_STORAGE_PROFILE
            profile.mark("journals")
            #endif
            try saveLifecycleUnlocked(state,replacing:replacing)
            compact.lifecycle=try lifecycleProjectionUnlocked(state.lifecycle)
            compact.history!.lifecycleCounts=try lifecycleCountsUnlocked()
            #if CHAI_STORAGE_PROFILE
            profile.mark("lifecycle")
            #endif
            try updatePerformance(state,replacing:replacing)
            #if CHAI_STORAGE_PROFILE
            profile.mark("performance")
            #endif
            try insert("INSERT INTO account_state(account_id,payload) VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload", [state.accountID,try json(compact)])
            #if CHAI_STORAGE_PROFILE
            profile.mark("projection_encode_write")
            #endif
            try exec("PRAGMA user_version=9; COMMIT")
            #if CHAI_STORAGE_PROFILE
            profile.mark("full_sync_commit")
            #endif
            cachedEquity=compact.equity;cachedEquityOffset=compact.history?.equityOffset ?? 0
            return compact
        } catch { try? exec("ROLLBACK"); throw error }
    }
    func readRows<T:Decodable>(_ type:T.Type,sql:String,values:[String]=[])throws->[T]{
        var rows:[T]=[]
        try visit(sql,values:values){rows.append(try JSONDecoder().decode(T.self,from:Data($0.utf8)))}
        return rows
    }
    func visit(_ sql:String,values:[String]=[],body:(String)throws->Void)throws{
        var stmt:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil)==SQLITE_OK else{throw TradeError.corrupt("歷史查詢準備失敗")}
        defer{sqlite3_finalize(stmt)}
        for (n,value) in values.enumerated(){_=value.withCString{sqlite3_bind_text(stmt,Int32(n+1),$0,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self))}}
        var status=sqlite3_step(stmt)
        var visited=0
        while status==SQLITE_ROW{if visited%256==0{try Task.checkCancellation()};visited+=1;guard let text=sqlite3_column_text(stmt,0) else{throw TradeError.corrupt("歷史資料損壞")};try ArchiveMemory.scoped{try body(String(cString:text))};status=sqlite3_step(stmt)}
        guard status==SQLITE_DONE else{throw TradeError.corrupt("歷史查詢中斷")}
    }
    public func auditEvent(id:String)throws->AuditEvent?{
        lock.lock();defer{lock.unlock()}
        return try readRows(AuditEvent.self,sql:"SELECT payload FROM events WHERE id=? AND account_id=? LIMIT 1",values:[id,mode.accountID]).first
    }
    /// Explicit full-history operation for backup/integrity checks, never used to render a screen.
    public func fullSnapshot(maximumExpandedBytes:Int?=nil)throws->AccountState?{
        lock.lock();defer{lock.unlock()}
        try exec("BEGIN DEFERRED")
        var committed=false
        defer{if !committed{try? exec("ROLLBACK")}}
        if let maximumExpandedBytes{
            guard maximumExpandedBytes>0,try legacyJSONLowerBoundUnlocked()<=Int64(maximumExpandedBytes) else{throw TradeError.invalid("此帳戶已超過舊格式備份容量。請使用上方完整檔案封存；原帳戶與歷史保留。")}
        }
        guard let json=try scalar("SELECT payload FROM account_state LIMIT 1") else{return nil}
        var s=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8))
        s.orders=Dictionary(uniqueKeysWithValues:try readRows(Order.self,sql:"SELECT payload FROM orders").map{($0.id,$0)})
        s.fills=try readRows(Fill.self,sql:"SELECT payload FROM fills ORDER BY rowid")
        s.events=try readRows(AuditEvent.self,sql:"SELECT payload FROM events ORDER BY sequence")
        s.ledger=try readRows(LedgerEntry.self,sql:"SELECT payload FROM ledger ORDER BY ordinal")
        s.equity=try readRows(EquityPoint.self,sql:"SELECT payload FROM equity ORDER BY ordinal")
        s.financialFlows=try readRows(FinancialFlow.self,sql:"SELECT payload FROM financial_flows ORDER BY rowid")
        if s.simulation != nil{let impacts=try SimulationParticipants.grouped(s.fills.compactMap(\.simulationImpact));if !impacts.isEmpty || s.simulation!.impactGroups != nil{s.simulation!.impactGroups=impacts};s.simulation!.impactArchiveCutoff=nil}
        s.appliedEvents=try appliedIDsUnlocked()
        s.journals=try fullJournalsUnlocked()
        s.lifecycle=try lifecycleProjectionUnlocked(s.lifecycle,full:true)
        s.history=nil;try Self.validate(s,mode:mode);try exec("COMMIT");committed=true;return s
    }
    public func simulationImpacts(instrumentID:String,from:Int64,through:Int64)throws->[SimulationImpact]{
        lock.lock();defer{lock.unlock()}
        let fills=try readRows(Fill.self,sql:"SELECT payload FROM fills WHERE json_extract(payload,'$.simulationImpact') IS NOT NULL AND json_extract(payload,'$.instrumentID')=? AND time>=? AND time<=? ORDER BY time,id",values:[instrumentID,String(from),String(through)])
        return try SimulationParticipants.grouped(fills.compactMap(\.simulationImpact))
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
        var output=Data();try writeCSVUnlocked(kind:kind,time:time){output.append($0)};return output
    }
    func writeCSVUnlocked(kind:String,time:Int64,consume:(Data)throws->Void)throws{
        guard let json=try scalar("SELECT payload FROM account_state LIMIT 1") else{throw TradeError.corrupt("帳戶不存在")}
        let s=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8))
        var first=true
        func emit(_ data:Data)throws{if !first{try consume(Data([13,10]))};first=false;try consume(data)}
        func write(_ row:[String])throws{try emit(Data(row.map(Analytics.csvCell).joined(separator:",").utf8))}
        let decoder=JSONDecoder()
        switch kind{
        case "fills":
            try write(Analytics.fillHeader)
            let prefix=["模擬交易",s.accountID,s.mode.rawValue,String(s.schema),String(time)].map(Analytics.csvCell).joined(separator:",")+","
            guard try scalar("SELECT count(*) FROM fill_report")==scalar("SELECT count(*) FROM fills") else{throw TradeError.corrupt("成交報表索引不完整，匯出中止")}
            try visit("SELECT r.cells FROM fills f JOIN fill_report r ON r.id=f.id ORDER BY f.rowid"){try emit(Data((prefix+$0).utf8))}
        case "ledger":
            try write(["模擬交易","accountID","exportedAt","eventID","time","currency","account","amount"])
            try visit("SELECT payload FROM ledger ORDER BY ordinal"){let e=try decoder.decode(LedgerEntry.self,from:Data($0.utf8));try write(["模擬交易",s.accountID,String(time),e.eventID,String(e.time),e.currency,e.account,e.amount.description])}
        case "orders":
            try write(Analytics.orderHeader)
            try visit("SELECT payload FROM orders ORDER BY time,id"){let o=try decoder.decode(Order.self,from:Data($0.utf8));try write(Analytics.orderRow(o,account:s,time:time))}
        default:throw TradeError.invalid("未知匯出類型")
        }
    }
    private func visitPerformance(from:Int64,until:Int64,body:(PerformanceInput)throws->Void)throws{
        let sql="""
        SELECT input FROM (
          SELECT 'F'||json_set(f.payload,'$.timelineSequence',coalesce(json_extract(f.payload,'$.timelineSequence'),e.sequence,0)) AS input,
            f.time AS time,coalesce(json_extract(f.payload,'$.timelineSequence'),e.sequence,0) AS sequence,0 AS kind,f.rowid AS ordinal
          FROM fills f LEFT JOIN events e ON e.id=f.id WHERE f.time>=? AND f.time<?
          UNION ALL
          SELECT 'G'||payload AS input,time,sequence,1 AS kind,rowid AS ordinal FROM financial_flows WHERE time>=? AND time<?
        ) ORDER BY time,sequence,kind,ordinal
        """
        let decoder=JSONDecoder()
        try visit(sql,values:[String(from),String(until),String(from),String(until)]){row in
            let data=Data(row.dropFirst().utf8)
            if row.first=="F"{try body(.fill(decoder.decode(Fill.self,from:data)))}else{try body(.flow(decoder.decode(FinancialFlow.self,from:data)))}
        }
    }
    private func updatePerformance(_ state:AccountState,replacing:Bool)throws{
        let decoder=JSONDecoder(),saved=try scalar("SELECT payload FROM report_state WHERE id=1").map{try decoder.decode(PerformanceCheckpoint.self,from:Data($0.utf8))}
        let offset=state.history?.fills ?? 0,total=offset+state.fills.count,flowOffset=state.history?.financialFlowOffset ?? 0,flowTotal=flowOffset+(state.financialFlows?.count ?? 0)
        var checkpoint=saved?.version==2 ? saved:nil
        var incoming:[PerformanceInput]=[]
        if !replacing,let value=checkpoint,value.processed>=offset,value.processed<=total,(value.processedFlows ?? 0)>=flowOffset,(value.processedFlows ?? 0)<=flowTotal{
            incoming=state.fills.dropFirst(value.processed-offset).map(PerformanceInput.fill)+(state.financialFlows ?? []).dropFirst((value.processedFlows ?? 0)-flowOffset).map(PerformanceInput.flow)
            if incoming.contains(where:{$0.time<value.lastTime || ($0.time==value.lastTime && $0.sequence<(value.lastSequence ?? 0))}){checkpoint=nil}
        }else{checkpoint=nil}
        if incoming.isEmpty && checkpoint != nil{return}
        if checkpoint==nil{try exec("DELETE FROM report_checkpoints")}
        var accumulator=PerformanceAccumulator(state:state,from:0,until:Int64.max,checkpoint:checkpoint,restoreTotals:true)
        var boundary=accumulator.processed+accumulator.processedFlows
        func include(_ input:PerformanceInput)throws{
            let processed=accumulator.processed+accumulator.processedFlows
            if processed-boundary>=1000 && input.time>accumulator.lastTime{
                let payload=String(decoding:try Self.encode(accumulator.checkpoint(totals:false)),as:UTF8.self)
                try insert("INSERT OR REPLACE INTO report_checkpoints(time,payload) VALUES(?,?)",[String(input.time),payload]);boundary=processed
            }
            try input.include(in:&accumulator)
        }
        if checkpoint==nil{
            try visitPerformance(from:0,until:Int64.max,body:include)
        }else{
            let sorted=incoming.enumerated().sorted{a,b in (a.element.time,a.element.sequence,a.offset)<(b.element.time,b.element.sequence,b.offset)}
            for row in sorted{try include(row.element)}
        }
        guard accumulator.processed==total,accumulator.processedFlows==flowTotal else{throw TradeError.corrupt("績效事件索引筆數不符，未保存變更")}
        try insert("INSERT INTO report_state(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",[String(decoding:try Self.encode(accumulator.checkpoint(totals:true)),as:UTF8.self)])
    }
    public func performance(from:Int64=0,until:Int64=Int64.max)throws->PerformanceReport{
        guard from>=0,until>from else{throw TradeError.invalid("報表日期範圍不合法")}
        lock.lock();defer{lock.unlock()}
        guard let json=try scalar("SELECT payload FROM account_state LIMIT 1") else{throw TradeError.corrupt("帳戶不存在")}
        let state=try JSONDecoder().decode(AccountState.self,from:Data(json.utf8)),decoder=JSONDecoder()
        if let text=try scalar("SELECT payload FROM report_state WHERE id=1"){
            let checkpoint=try decoder.decode(PerformanceCheckpoint.self,from:Data(text.utf8))
            if checkpoint.version==2,from <= (checkpoint.firstTime ?? 0),until>checkpoint.lastTime,var report=checkpoint.report{
                report.from=from;report.until=until;let v=try Analytics.valuation(state);report.valuationComplete=v.complete;report.valuationMissing=v.missing;return report
            }
        }
        let checkpoint=try readRows(PerformanceCheckpoint.self,sql:"SELECT payload FROM report_checkpoints WHERE time<=? ORDER BY time DESC LIMIT 1",values:[String(from)]).first.flatMap{$0.version==2 ? $0:nil}
        var accumulator=PerformanceAccumulator(state:state,from:from,until:until,checkpoint:checkpoint)
        let start=checkpoint.map{$0.lastTime+1} ?? 0
        try visitPerformance(from:start,until:until){try $0.include(in:&accumulator)}
        return accumulator.report
    }

}

public struct AppSettings: Codable, Sendable {
    public var activeMode: Mode = .offline
    public var pendingMode: Mode?
    public var pendingNotice:NoticeLink?
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
