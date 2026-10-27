import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

private func sql(_ path:String,_ command:String)throws{
    var db:OpaquePointer?
    guard sqlite3_open(path,&db)==SQLITE_OK else{throw TradeError.corrupt("test database")}
    defer{sqlite3_close(db)}
    guard sqlite3_exec(db,command,nil,nil,nil)==SQLITE_OK else{throw TradeError.corrupt("test SQL")}
}
@Test func schemaOneMigrationRollbackAndRetryPreservesOriginal()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let dir=root.appendingPathComponent("accounts/account-online")
    try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    let path=dir.appendingPathComponent("account.sqlite").path
    let old=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    let payload=String(decoding:try AccountRepository.encode(old),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    try sql(path,"CREATE TABLE account_state(account_id TEXT PRIMARY KEY,payload TEXT NOT NULL); INSERT INTO account_state VALUES('account-online','\(payload)'); CREATE TABLE ledger(ordinal INTEGER PRIMARY KEY,account_id TEXT NOT NULL,payload TEXT NOT NULL); CREATE TRIGGER fail_migration BEFORE INSERT ON ledger BEGIN SELECT RAISE(ABORT,'injected interruption'); END; PRAGMA user_version=1;")
    #expect(throws:TradeError.self){_ = try AccountRepository(root:root,mode:.online)}
    // No deletion/replacement was committed by the failed migration. The same source can retry.
    try sql(path,"DROP TRIGGER fail_migration")
    let repository=try AccountRepository(root:root,mode:.online)
    let full=try #require(try repository.fullSnapshot())
    #expect(full.cash==old.cash);#expect(full.ledger.count==old.ledger.count);#expect(full.events.count==old.events.count)
    #expect(try repository.load()?.schema==1)
}
@Test func failedAppendRollsBackHistoryAndProjectionTogether()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online),ctx=AccountContext(mode:.online)
    let initial=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial)
    try sql(repo.path,"CREATE TRIGGER fail_append BEFORE INSERT ON ledger WHEN NEW.ordinal>2 BEGIN SELECT RAISE(ABORT,'injected failure'); END;")
    await #expect(throws:TradeError.self){try await engine.cashFlow(currency:"TWD",amount:Amount("123"),time:1005,eventID:"must-rollback",context:ctx)}
    #expect(await engine.snapshot().cash==initial.cash)
    #expect(try repo.fullSnapshot()?.events.count==initial.events.count)
    #expect(try repo.fullSnapshot()?.ledger.count==2)
    try sql(repo.path,"DROP TRIGGER fail_append")
    try await engine.cashFlow(currency:"TWD",amount:Amount("123"),time:1005,eventID:"must-rollback",context:ctx)
    #expect(try repo.fullSnapshot()?.cash["TWD"]==Amount("100123"))
}
@Test func compressedBackupRoundTripAndExpansionBombRejected()throws{
    var state=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    for n in 0..<500{state.journals.append(JournalEntry(text:String(repeating:"本機合成測試",count:100),tags:"synthetic",time:Int64(n)))}
    let data=try BackupService.export(state,password:"test-password",time:1000)
    let envelope=try JSONDecoder().decode(BackupEnvelope.self,from:data)
    #expect(envelope.compression=="zlib-1")
    #expect(data.count<100_000)
    #expect(try BackupService.validate(data,expectedMode:.online,password:"test-password").journals.count==500)
    var bad=envelope;bad.expandedSize=Int.max
    #expect(throws:TradeError.self){try BackupService.validate(AccountRepository.encode(bad),expectedMode:.online,password:"test-password")}
    var partial=state;var history=HistoryWindow();history.fills=1;partial.history=history
    #expect(throws:TradeError.self){try BackupService.export(partial,password:nil,time:1000)}
}
@Test func orderPagesDoNotLoseEqualTimeRows()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online)
    var s=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    let instrument=s.instruments[0]
    for n in 0..<350{
        var request=OrderRequest(instrumentID:instrument.id,side:.buy,kind:.limit,quantity:.one,price:try Amount("1"));request.requestID=String(format:"order-%03d",n)
        s.orders[request.requestID]=Order(id:request.requestID,accountID:s.accountID,request:request,status:.cancelled,referencePrice:.one,createdAt:1000,updatedAt:1000,ruleVersion:instrument.rules.version)
    }
    try repo.save(s)
    var found:[Order]=[],time:Int64?,id:String?
    while true{let page=try repo.orderPage(limit:100,before:time,beforeID:id,search:instrument.id);if page.isEmpty{break};found+=page;time=page.last?.updatedAt;id=page.last?.id}
    #expect(found.count==350);#expect(Set(found.map(\.id)).count==350)
    #expect(try repo.load()!.orders.count==100)
}
@Test func schemaTwoArchivedHistoryMigratesToAtomicReportIndex()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online)
    let repo=try AccountRepository(root:root,mode:.online),initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount("100000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial),id=initial.instruments[0].id
    let q=Quote(instrumentID:id,source:"synthetic-migration-fixture",time:1000,sequence:1000,last:try Amount("100"),bids:[Level(try Amount("99.99"),try Amount("1000"))],asks:[Level(try Amount("100"),try Amount("1000"))])
    try await engine.ingest(q,now:1000,context:ctx)
    for n in 0..<120{var request=OrderRequest(instrumentID:id,side:.buy,kind:.market,quantity:.one);request.requestID="migration-\(n)";_=try await engine.submit(request,time:1000,context:ctx)}
    let before=try #require(try repo.fullSnapshot())
    #expect(try repo.load()?.history?.fills==20)
    try sql(repo.path,"DELETE FROM report_state; DELETE FROM report_checkpoints; PRAGMA user_version=2; CREATE TRIGGER fail_report BEFORE INSERT ON report_state BEGIN SELECT RAISE(ABORT,'injected interruption'); END;")
    #expect(throws:TradeError.self){_=try AccountRepository(root:root,mode:.online)}
    try sql(repo.path,"DROP TRIGGER fail_report")
    let migrated=try AccountRepository(root:root,mode:.online),after=try #require(try migrated.fullSnapshot())
    #expect(after.cash==before.cash);#expect(after.fills.count==120);#expect(after.ledger.count==before.ledger.count)
    #expect(try migrated.performance().currencies["USD"]?.count==120)
}
@Test func schemaThreeEquityMigrationRollsBackAndRetainsAllPoints()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),repo=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount("1000"),time:1000)
    for n in 1..<5000{state.equity.append(EquityPoint(time:Int64(1000+n),value:try Amount("1000"),flow:.zero))}
    try repo.save(state)
    let old=String(decoding:try AccountRepository.encode(state),as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    try sql(repo.path,"DELETE FROM equity; UPDATE account_state SET payload='\(old)'; PRAGMA user_version=3; CREATE TRIGGER fail_equity BEFORE INSERT ON equity BEGIN SELECT RAISE(ABORT,'injected migration interruption'); END;")
    #expect(throws:TradeError.self){_=try AccountRepository(root:root,mode:.online)}
    try sql(repo.path,"DROP TRIGGER fail_equity")
    let migrated=try AccountRepository(root:root,mode:.online)
    #expect(try migrated.load()?.equity.count==1000)
    #expect(try migrated.fullSnapshot()?.equity==state.equity)
    #expect(try migrated.equityPage(limit:100).count==100)
}
