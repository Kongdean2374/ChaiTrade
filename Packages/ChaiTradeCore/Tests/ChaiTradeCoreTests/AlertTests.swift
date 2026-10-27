import Foundation
import Testing
@testable import ChaiTradeCore

private struct AlertRig{
    let context=AccountContext(mode:.online)
    let repository:AccountRepository
    let engine:TradingEngine
    let instrument:Instrument
    init()throws{
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        instrument=Instrument(id:"TEST:ALERT",symbol:"TEST",name:"合成提醒驗證",asset:.crypto,currency:"USD",rules:try RulePack(tick:Amount("0.01"),quantityStep:.one),initialPrice:try Amount(100))
        var initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount(1000),time:1000);initial.instruments=[instrument]
        repository=try AccountRepository(root:root,mode:.online);engine=try TradingEngine(context:context,repository:repository,initial:initial)
    }
    func quote(_ price:Int,time:Int64=1000)throws->Quote{
        Quote(instrumentID:instrument.id,source:"synthetic-alert-test",time:time,sequence:time,last:try Amount(price),bids:[Level(try Amount(price-1),.one)],asks:[Level(try Amount(price+1),.one)])
    }
}
@Test func percentageAlertFreezesExactBasisFiresOnceAndSurvivesRestart()async throws{
    let r=try AlertRig(),ctx=r.context
    try await r.engine.ingest(r.quote(100),now:1000,context:ctx)
    try await r.engine.addPercentageAlert(id:"fixed-five",instrumentID:r.instrument.id,percentage:Amount(5),above:true,time:1000,context:ctx)
    let created=try #require(await r.engine.snapshot().alerts.first)
    #expect(created.price == (try Amount(105)));#expect(created.baseline == (try Amount(100)));#expect(created.baselineTime==1000)
    await #expect(throws:TradeError.self){try await r.engine.addPercentageAlert(id:"fixed-five",instrumentID:r.instrument.id,percentage:Amount(5),above:true,time:1000,context:ctx)}
    var stale=try r.quote(120,time:1001);stale.quality = .delayed
    try await r.engine.ingest(stale,now:1001,context:ctx)
    #expect(await r.engine.snapshot().alerts.first?.firedAt==nil)
    try await r.engine.ingest(r.quote(104,time:1002),now:1002,context:ctx)
    #expect(await r.engine.snapshot().alerts.first?.firedAt==nil)
    try await r.engine.ingest(r.quote(105,time:1003),now:1003,context:ctx)
    let next=AccountContext(mode:.online),reopened=try TradingEngine(context:next,repository:r.repository,initial:#require(try r.repository.load()))
    try await reopened.ingest(r.quote(110,time:1004),now:1004,context:next)
    let full=try await reopened.fullSnapshot(context:next)
    #expect(full.events.filter{$0.kind=="priceAlert"}.count==1);#expect(full.inbox?.filter{$0.event.kind=="priceAlert"}.count==1)
    #expect(full.alerts.first?.baseline == (try Amount(100)));#expect(full.cash["USD"] == (try Amount(1000)))
    let link=try NoticeLink(accountID:next.accountID,eventID:"alert-fixed-five")
    let destination=try await reopened.noticeDestination(link,context:next)
    #expect(destination.instrument?.id==r.instrument.id);#expect(!destination.opensOrders)
    await #expect(throws:TradeError.self){try await reopened.noticeDestination(NoticeLink(accountID:Mode.offline.accountID,eventID:link.eventID),context:next)}
    await #expect(throws:TradeError.self){try await reopened.noticeDestination(NoticeLink(accountID:next.accountID,eventID:"not-an-event"),context:next)}
}
@Test func percentageAlertRequiresFreshReferenceAndRejectsInvalidDownside()async throws{
    let r=try AlertRig(),ctx=r.context
    try await r.engine.ingest(r.quote(100),now:1000,context:ctx)
    await #expect(throws:TradeError.self){try await r.engine.addPercentageAlert(instrumentID:r.instrument.id,percentage:Amount(5),above:true,basis:.sourceReference,time:1000,context:ctx)}
    await #expect(throws:TradeError.self){try await r.engine.addPercentageAlert(instrumentID:r.instrument.id,percentage:Amount(100),above:false,time:1000,context:ctx)}
    await #expect(throws:TradeError.self){try await r.engine.addPercentageAlert(instrumentID:r.instrument.id,percentage:Amount(5),above:false,time:1100,context:ctx)}
    try await r.engine.addPercentageAlert(instrumentID:r.instrument.id,percentage:Amount(5),above:false,time:1000,context:ctx)
    #expect(await r.engine.snapshot().alerts.first?.price == (try Amount(95)))
    try await r.engine.ingest(r.quote(95,time:1001),now:1001,context:ctx)
    #expect(await r.engine.snapshot().alerts.first?.firedAt==1001)
    #expect(throws:TradeError.self){try NoticeLink(accountID:"foreign",eventID:"event")}
    #expect(throws:(any Error).self){try JSONDecoder().decode(NoticeLink.self,from:Data("{\"accountID\":\"foreign\",\"eventID\":\"event\"}".utf8))}
}
