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
@Test func completeProjectionSurvivesEquityWindowSlidesRollbackAndReload()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online)
    var original=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    for n in 1...1500{
        let value:Amount?=n.isMultiple(of:11) ? nil:try Amount(String(100000+n)+".125")
        original.equity.append(EquityPoint(time:Int64(1000+n),value:value,flow:.zero))
    }
    var expected=original.equity,hot=try repo.save(original)
    func checkProjection(_ value:AccountState)throws{
        let payload=try #require(try repo.scalar("SELECT payload FROM account_state"))
        let decoded=try JSONDecoder().decode(AccountState.self,from:Data(payload.utf8))
        #expect(decoded.equity.count==1000,"The complete original hot window must remain persisted")
        #expect(decoded.equity==value.equity)
        #expect(try AccountRepository.encode(decoded)==AccountRepository.encode(value))
        #expect(try repo.scalar("PRAGMA synchronous")=="2")
    }
    try checkProjection(hot)
    for n in 1...8{
        let value:Amount?=n.isMultiple(of:3) ? nil:try Amount(String(110000+n)+".375")
        let point=EquityPoint(time:Int64(2500+n),value:value,flow:.zero)
        hot.equity.append(point);expected.append(point);hot=try repo.save(hot)
        try checkProjection(hot)
    }
    let archive=root.appendingPathComponent("projection-before-more-writes.sqlite")
    try repo.createArchiveSnapshot(at:archive)
    let archivedHot=hot,archivedEquity=expected
    let before=try repo.scalar("SELECT payload FROM account_state")
    var rejected=hot;rejected.equity[500].value=try Amount("999999.99")
    rejected.equity.append(EquityPoint(time:2509,value:try Amount("123456.75"),flow:.zero))
    #expect(throws:TradeError.self){try repo.save(rejected)}
    #expect(try repo.scalar("SELECT payload FROM account_state")==before)
    // Abort after the new projection has been assembled, not only at the
    // earlier immutable-point guard. Neither SQL nor encoding caches may advance.
    try sql(repo.path,"CREATE TRIGGER fail_projection BEFORE UPDATE ON account_state BEGIN SELECT RAISE(ABORT,'injected projection failure'); END")
    var failedCommit=hot
    failedCommit.equity.append(EquityPoint(time:2509,value:try Amount("998877.125"),flow:.zero))
    #expect(throws:TradeError.self){try repo.save(failedCommit)}
    #expect(try repo.scalar("SELECT payload FROM account_state")==before)
    #expect(try repo.scalar("SELECT count(*) FROM equity")==String(expected.count))
    try sql(repo.path,"DROP TRIGGER fail_projection")
    // A failed attempt must not poison the bytes reused by the next real commit.
    let next=EquityPoint(time:2509,value:try Amount("112233.875"),flow:.zero)
    hot.equity.append(next);expected.append(next);hot=try repo.save(hot);try checkProjection(hot)
    hot=try #require(try repo.load())
    let afterReload=EquityPoint(time:2510,value:nil,flow:.zero)
    hot.equity.append(afterReload);expected.append(afterReload);hot=try repo.save(hot);try checkProjection(hot)
    let full=try #require(try repo.fullSnapshot())
    #expect(full.equity==expected);#expect(full.cash==original.cash)
    let reopened=try AccountRepository(root:root,mode:.online)
    #expect(try reopened.load()?.equity==hot.equity)
    #expect(try reopened.fullSnapshot()?.equity==expected)
    // Replacing the database on an already-used repository must invalidate all
    // former window bytes, including the same-sized window of a later timeline.
    let verified=try SQLiteArchiveDatabase.verify(archive,mode:.online)
    _=try repo.installArchiveSnapshot(verified)
    hot=try repo.save(archivedHot);try checkProjection(hot)
    #expect(try repo.fullSnapshot()?.equity==archivedEquity)
}
@Test(arguments:["events","ledger"])
func reusedDuplicateChecksStillBindEveryIdentityAndRejectChangedContent(_ table:String)throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online)
    var original=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    for n in 0..<4{
        let id="immutable-binding-\(n)"
        original.post(event:id,currency:"TWD",debit:"synthetic-left",credit:"synthetic-right",amount:.one,time:Int64(1010+n))
        original.audit("fixture","different content \(n)",time:Int64(1010+n),id:id)
    }
    let saved=try repo.save(original)
    _=try repo.save(saved) // Several distinct duplicate keys use the same prepared check.
    let before=try repo.scalar("SELECT payload FROM account_state")
    var rejected=saved
    if table=="events"{
        rejected.events[3].message="changed immutable content"
    }else{
        // Keep the group balanced and cash unchanged so validation reaches the
        // canonical-row comparison rather than failing an unrelated money guard.
        let old=rejected.ledger[6].amount
        rejected.ledger[6].amount=try old+old;rejected.ledger[7].amount=rejected.ledger[6].amount.negated
    }
    #expect(throws:TradeError.self){try repo.save(rejected)}
    #expect(try repo.scalar("SELECT payload FROM account_state")==before)
    _=try repo.save(saved)
    let full=try #require(try repo.fullSnapshot())
    #expect(full.cash==original.cash)
    #expect(try AccountRepository.encode(full.events)==AccountRepository.encode(original.events))
    #expect(try AccountRepository.encode(full.ledger)==AccountRepository.encode(original.ledger))
    #expect(try repo.scalar("PRAGMA synchronous")=="2")
}
@Test(arguments:["ledger","equity"])
func indexedExactCountsStillRejectArchivedHistoryHoles(_ table:String)throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount("100000"),time:1000)
    for n in 1...1200{
        let id="count-hole-\(n)",time=Int64(1000+n)
        state.post(event:id,currency:"TWD",debit:"synthetic-count",credit:"synthetic-offset",amount:.one,time:time)
        state.audit("fixture","exact count preservation",time:time,id:id)
        state.equity.append(EquityPoint(time:time,value:state.cash["TWD"],flow:.zero))
    }
    var hot=try repo.save(state)
    let payload=try repo.scalar("SELECT payload FROM account_state")
    let countText=try #require(try repo.scalar("SELECT count(*) FROM \(table)"))
    let count=try #require(Int(countText))
    try sql(repo.path,"DELETE FROM \(table) WHERE ordinal=1")
    let instrument=try #require(hot.instruments.first);hot.watchlist.insert(instrument.id)
    #expect(throws:TradeError.self){try repo.save(hot)}
    #expect(try repo.scalar("SELECT payload FROM account_state")==payload)
    #expect(try repo.scalar("SELECT count(*) FROM \(table)")==String(count-1))
    #expect(try repo.scalar("PRAGMA synchronous")=="2")
}
@Test func priorArchiveWithoutCountIndexesRestoresAndStillRejectsCustomSQL()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repo=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount("123456"),time:1000)
    for n in 1...1100{state.equity.append(EquityPoint(time:Int64(1000+n),value:state.cash["TWD"],flow:.zero))}
    _=try repo.save(state)
    let original=try #require(try repo.fullSnapshot()),file=root.appendingPathComponent("prior-schema9.sqlite")
    try repo.createArchiveSnapshot(at:file)
    try sql(file.path,"DROP INDEX ledger_account_count; DROP INDEX equity_account_count")
    let before=try ArchiveDigest.file(file),verified=try SQLiteArchiveDatabase.verify(file,mode:.online)
    #expect(try ArchiveDigest.file(file)==before,"Verification must not migrate the imported file")
    let targetRoot=root.appendingPathComponent("restored"),target=try AccountRepository(root:targetRoot,mode:.online)
    _=try target.installArchiveSnapshot(verified)
    let reopened=try AccountRepository(root:targetRoot,mode:.online),full=try #require(try reopened.fullSnapshot())
    #expect(full.cash==original.cash);#expect(try AccountRepository.encode(full.ledger)==AccountRepository.encode(original.ledger));#expect(full.equity==original.equity)
    #expect(try reopened.scalar("SELECT count(*) FROM sqlite_schema WHERE type='index' AND name IN ('ledger_account_count','equity_account_count')")=="2")
    try sql(file.path,"CREATE TRIGGER unexpected_archive_sql AFTER INSERT ON ledger BEGIN SELECT 1; END")
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(file,mode:.online)}
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
