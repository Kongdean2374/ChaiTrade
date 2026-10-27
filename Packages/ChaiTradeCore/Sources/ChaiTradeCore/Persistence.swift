import Foundation
import CSQLite

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
            guard Int(version) ?? 99 <= 1 else { throw TradeError.corrupt("資料庫版本較新，請更新 App；不可降版覆寫") }
            try exec("BEGIN IMMEDIATE; CREATE TABLE IF NOT EXISTS account_state (account_id TEXT PRIMARY KEY, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, account_id TEXT NOT NULL, sequence INTEGER NOT NULL UNIQUE, payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS fills (id TEXT PRIMARY KEY, order_id TEXT NOT NULL, account_id TEXT NOT NULL, time INTEGER NOT NULL, payload TEXT NOT NULL); CREATE INDEX IF NOT EXISTS fills_time ON fills(time); CREATE INDEX IF NOT EXISTS fills_order ON fills(order_id); PRAGMA user_version=1; COMMIT;")
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
        try Self.validate(state, mode: mode)
        return state
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
        let groups = Dictionary(grouping: state.ledger, by: { "\($0.eventID)|\($0.currency)" })
        for entries in groups.values where try sum(entries.map(\.amount)) != .zero { throw TradeError.corrupt("帳本不平衡，拒絕載入或寫入") }
        guard Set(state.fills.map(\.id)).count == state.fills.count, Set(state.events.map(\.id)).count == state.events.count else { throw TradeError.corrupt("重複事件或成交") }
    }
    public func save(_ state: AccountState, replacing: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        try Self.validate(state, mode: mode)
        let json = String(decoding: try Self.encode(state), as: UTF8.self)
        try exec("BEGIN IMMEDIATE")
        do {
            if replacing { try exec("DELETE FROM events; DELETE FROM fills;") }
            for event in state.events {
                try insert("INSERT OR IGNORE INTO events(id,account_id,sequence,payload) VALUES(?,?,?,?)", [event.id,state.accountID,String(event.sequence),String(decoding: try Self.encode(event), as: UTF8.self)])
            }
            for fill in state.fills {
                try insert("INSERT OR IGNORE INTO fills(id,order_id,account_id,time,payload) VALUES(?,?,?,?,?)", [fill.id,fill.orderID,state.accountID,String(fill.time),String(decoding: try Self.encode(fill), as: UTF8.self)])
            }
            try insert("INSERT INTO account_state(account_id,payload) VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET payload=excluded.payload", [state.accountID,json])
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
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
