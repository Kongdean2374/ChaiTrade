import Foundation
import Testing
import CSQLite
@testable import ChaiTradeCore

@Test func archivedIdempotencySurvivesHotPruningRestartBackupRestoreAndAccountIsolation()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let repository=try AccountRepository(root:root,mode:.online),context=AccountContext(mode:.online)
    let initial=try TradingEngine.initial(mode:.online,capital:Amount(1000),time:1000),engine=try TradingEngine(context:context,repository:repository,initial:initial)
    for n in 0..<240{try await engine.cashFlow(currency:"TWD",amount:Amount(1),time:Int64(1001+n),eventID:String(format:"flow-%04d",n),context:context)}
    let hot=await engine.snapshot();#expect(hot.appliedEvents.count==100 && hot.history?.appliedEventCount==241)
    #expect(!hot.appliedEvents.contains("flow-0000"));#expect(try repository.appliedEventExists("flow-0000"))
    try await engine.cashFlow(currency:"TWD",amount:Amount(999),time:2000,eventID:"flow-0000",context:context)
    #expect(try AccountRepository.encode(await engine.snapshot())==AccountRepository.encode(hot))
    let next=AccountContext(mode:.online),reopened=try TradingEngine(context:next,repository:repository,initial:#require(try repository.load()))
    try await reopened.cashFlow(currency:"TWD",amount:Amount(999),time:2000,eventID:"flow-0000",context:next)
    #expect(await reopened.snapshot().cash==hot.cash)
    let full=try await reopened.fullSnapshot(context:next);#expect(full.appliedEvents.count==241)
    #expect(throws:TradeError.self){try BackupService.export(hot,password:nil,time:2000)}
    let backup=try BackupService.export(full,password:nil,time:2000),restored=try BackupService.validate(backup,expectedMode:.online,password:nil)
    let restoreRepository=try AccountRepository(root:root.appendingPathComponent("restored"),mode:.online),restoreContext=AccountContext(mode:.online)
    let restoreEngine=try TradingEngine(context:restoreContext,repository:restoreRepository,initial:restored)
    try await restoreEngine.cashFlow(currency:"TWD",amount:Amount(999),time:2000,eventID:"flow-0000",context:restoreContext)
    #expect(await restoreEngine.snapshot().cash==hot.cash)
    let offlineContext=AccountContext(mode:.offline),offline=try TradingEngine(context:offlineContext,repository:AccountRepository(root:root,mode:.offline),initial:TradingEngine.initial(mode:.offline,capital:Amount(1000),time:1000))
    try await offline.cashFlow(currency:"TWD",amount:Amount(2),time:2000,eventID:"flow-0000",context:offlineContext)
    #expect(try await offline.snapshot().cash["TWD"]==Amount(1002));#expect(await reopened.snapshot().cash==hot.cash)
    let snapshot=root.appendingPathComponent("tampered.sqlite");try repository.createArchiveSnapshot(at:snapshot)
    var database:OpaquePointer?;#expect(sqlite3_open(snapshot.path,&database)==SQLITE_OK)
    #expect(sqlite3_exec(database,"UPDATE applied_event_ids SET rowid=999999 WHERE id='flow-0000'",nil,nil,nil)==SQLITE_OK);sqlite3_close(database)
    #expect(throws:TradeError.self){try SQLiteArchiveDatabase.verify(snapshot,mode:.online)}
    #expect(try repository.load()?.cash==hot.cash)
}

@Test func legacyStateWithoutRuntimeLookupAndSchemaSevenMigrationKeepExactCashAndIDs()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    var original=try TradingEngine.initial(mode:.online,capital:Amount(2500),time:1000)
    original.appliedEvents.formUnion((0..<300).map{"legacy-id-\($0)"})
    var object=try #require(try JSONSerialization.jsonObject(with:AccountRepository.encode(original)) as? [String:Any]);object.removeValue(forKey:"archivedAppliedLookup")
    let raw=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),legacy=try JSONDecoder().decode(AccountState.self,from:raw)
    #expect(try legacy.hasApplied("legacy-id-0"));#expect(try !legacy.hasApplied("unknown"))
    let path=root.appendingPathComponent("accounts/\(Mode.online.accountID)/account.sqlite").path
    do{let repository=try AccountRepository(root:root,mode:.online);_=try repository.save(original)}
    var database:OpaquePointer?;#expect(sqlite3_open(path,&database)==SQLITE_OK)
    let json=String(decoding:raw,as:UTF8.self).replacingOccurrences(of:"'",with:"''")
    #expect(sqlite3_exec(database,"DROP TABLE applied_event_ids; UPDATE account_state SET payload='\(json)'; PRAGMA user_version=7",nil,nil,nil)==SQLITE_OK);sqlite3_close(database)
    let migrated=try AccountRepository(root:root,mode:.online),hot=try #require(try migrated.load())
    #expect(hot.cash==original.cash && hot.appliedEvents.count==100 && hot.history?.appliedEventCount==301)
    #expect(try migrated.fullSnapshot()?.appliedEvents==original.appliedEvents);#expect(try migrated.appliedEventExists("legacy-id-0"))
}
