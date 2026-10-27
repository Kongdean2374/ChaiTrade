import Foundation
import Testing
@testable import ChaiTradeCore

@Test func chartJournalAndNotificationStateSurviveRestartAndBackup()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online)
    let repo=try AccountRepository(root:root,mode:.online)
    let initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount("100000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial),id=initial.instruments[0].id
    try await engine.saveChartPreferences(instrumentID:id,preferences:ChartPreferences(interval:604800,indicator:"RSI",period:14,line:true),context:ctx)
    try await engine.configureNotifications(true,context:ctx)
    let q=Quote(instrumentID:id,source:"synthetic-feature-fixture",time:1000,sequence:1000,last:try Amount("100"),bids:[Level(try Amount("99.99"),try Amount("1000"))],asks:[Level(try Amount("100"),try Amount("1000"))])
    try await engine.ingest(q,now:1000,context:ctx)
    var request=OrderRequest(instrumentID:id,side:.buy,kind:.market,quantity:.one);request.requestID="stable-feature-order"
    _=try await engine.submit(request,time:1000,context:ctx)
    _=try await engine.submit(request,time:1000,context:ctx)
    var s=await engine.snapshot()
    #expect(s.inbox?.filter{$0.event.kind=="fill"}.count==1)
    let notice=try #require(s.inbox?.first)
    #expect(!notice.delivered);#expect(notice.accountID==ctx.accountID)
    try await engine.acknowledgeNotices([notice.id],context:ctx)
    var journal=JournalEntry(text:"自行生成的檢討測試",tags:"strategy",time:1000)
    journal.orderID=request.requestID;journal.instrumentID=id;journal.emotion="calm"
    journal.screenshot=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l1sAAAAASUVORK5CYII=")!
    try await engine.recordJournal(journal,context:ctx)
    s=try await engine.fullSnapshot(context:ctx)
    let backup=try BackupService.export(s,password:"test-password",time:1000)
    let restored=try BackupService.validate(backup,expectedMode:.online,password:"test-password")
    #expect(restored.chartPreferences?[id]?.interval==604800)
    #expect(restored.chartPreferences?[id]?.indicator=="RSI")
    #expect(restored.journals.first?.screenshot==journal.screenshot)
    #expect(restored.inbox?.first?.delivered==true)
    let reopened=try TradingEngine(context:AccountContext(mode:.online),repository:repo,initial:repo.load()!)
    #expect(await reopened.snapshot().inbox?.filter{!$0.delivered}.isEmpty==true)
    await #expect(throws:TradeError.self){try await reopened.acknowledgeNotices([notice.id],context:ctx)}
}
@Test func journalRejectsCrossAccountOrderAndOversizeImage()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online)
    let repo=try AccountRepository(root:root,mode:.online),initial=try TradingEngine.initial(mode:.online,capital:Amount("1000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial)
    var journal=JournalEntry(text:"synthetic",tags:"",time:1000);journal.orderID="other-account-order"
    let invalidOrder=journal
    await #expect(throws:TradeError.self){try await engine.recordJournal(invalidOrder,context:ctx)}
    journal.orderID=nil;journal.screenshot=Data(repeating:0,count:2_000_001)
    let invalidImage=journal
    await #expect(throws:TradeError.self){try await engine.recordJournal(invalidImage,context:ctx)}
    #expect(await engine.snapshot().journals.isEmpty)
}
@Test func maintenanceProtectsRecoveryPointAndReleasesOnFailure()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online)
    let repo=try AccountRepository(root:root,mode:.online),initial=try TradingEngine.initial(mode:.online,capital:Amount("1000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial)
    let (token,recovery)=try await engine.beginMaintenance(context:ctx)
    #expect(recovery.cash==initial.cash)
    await #expect(throws:TradeError.self){try await engine.cashFlow(currency:"TWD",amount:Amount("1"),time:1001,context:ctx)}
    await #expect(throws:TradeError.self){try await engine.restore(initial,maintenanceToken:UUID(),context:ctx)}
    try await engine.endMaintenance(token:token,context:ctx)
    try await engine.cashFlow(currency:"TWD",amount:Amount("1"),time:1001,context:ctx)
    #expect(try await engine.snapshot().cash["TWD"]==Amount("1001"))
    let (second,snapshot)=try await engine.beginMaintenance(context:ctx)
    try await engine.restore(snapshot,maintenanceToken:second,context:ctx)
    try await engine.cashFlow(currency:"TWD",amount:Amount("1"),time:1002,context:ctx)
    #expect(try await engine.snapshot().cash["TWD"]==Amount("1002"))
}
private final class TestWallClock:@unchecked Sendable{
    private let lock=NSLock();private var value:Int64=1000
    func read()->Int64{lock.lock();defer{lock.unlock()};return value}
    func advance(){lock.lock();value=1060;lock.unlock()}
}
@Test func queuedOrdersUseExecutionTimeForQuoteFreshness()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.online),clock=TestWallClock()
    let repo=try AccountRepository(root:root,mode:.online),initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount("1000"),time:1000)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial,wallClock:{clock.read()}),id=initial.instruments[0].id
    let q=Quote(instrumentID:id,source:"synthetic-clock-fixture",time:1000,sequence:1000,last:try Amount("100"),bids:[Level(try Amount("99.99"),try Amount("1000"))],asks:[Level(try Amount("100"),try Amount("1000"))])
    try await engine.ingest(q,now:1000,context:ctx)
    var resting=OrderRequest(instrumentID:id,side:.buy,kind:.limit,quantity:.one,price:try Amount("90"));resting.requestID="aged-amendment"
    _=try await engine.submit(resting,time:1000,context:ctx);clock.advance()
    try await engine.amend(id:resting.requestID,quantity:.one,price:Amount("100"),time:1000,context:ctx)
    _=try await engine.submit(OrderRequest(instrumentID:id,side:.buy,kind:.market,quantity:.one),time:1000,context:ctx)
    #expect(await engine.snapshot().fills.isEmpty)
    #expect(try await engine.snapshot().cash["USD"]==Amount("1000"))
}
