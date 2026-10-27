import Foundation
import Testing
@testable import ChaiTradeCore

private struct ScheduleRig{
    let root:URL,repo:AccountRepository,context:AccountContext,engine:TradingEngine,instrument:Instrument
    init(future:Bool=false,time:Int64=1000,zone:String="UTC",minute:Int=17,expiry:Int64=1035)throws{
        root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);context=AccountContext(mode:.offline);repo=try AccountRepository(root:root,mode:.offline)
        var rules=RulePack(tick:try Amount("0.01"),quantityStep:.one)
        if future{rules.multiplier=try Amount("3");rules.expiry=expiry;rules.dailySettlementMinute=minute;rules.timeZone=zone}
        else{rules.carrySchedule=CarrySchedule(interval:10,longRate:try Amount("0.01"),shortRate:try Amount("-0.01"))}
        instrument=Instrument(id:"SIM:SCHEDULE",symbol:"SCHEDULE",name:"合成排程測試",asset:future ? .future:.perpetual,currency:"TWD",rules:rules,initialPrice:try Amount("100"))
        var state=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:1000);state.instruments=[instrument];state.simulation!.time=time;state.leverageEnabled=true
        for n in state.equity.indices{state.equity[n].time=time};for n in state.ledger.indices{state.ledger[n].time=time};for n in state.events.indices{state.events[n].time=time;state.events[n].capitalFlow?.time=time}
        engine=try TradingEngine(context:context,repository:repo,initial:state)
    }
    func open(_ side:Side)async throws{
        try await engine.initializeQuotes(context:context)
        var request=OrderRequest(instrumentID:instrument.id,side:side,kind:.market,quantity:try Amount("2"));request.requestID="schedule-open"
        _=try await engine.submit(request,time:1000,context:context)
    }
}
@Test func offlineFundingScheduleIsExactSignedAndReplaySafe()async throws{
    for side in [Side.buy,.sell]{
        let rig=try ScheduleRig();try await rig.open(side)
        let before=await rig.engine.snapshot()
        _=try await rig.engine.advance(to:1010,context:rig.context)
        let first=await rig.engine.snapshot(),carry=try #require(first.lifecycle?.carry.first)
        let mark=try Simulation.price(rig.instrument,at:1010,state:first.simulation!),cost=try mark*Amount("2")*Amount(side == .buy ? "0.01":"-0.01")
        #expect(carry.amount==cost);#expect(carry.calculationModel=="absolute-notional-side-rate-1")
        #expect(try first.cash["TWD"]==before.cash["TWD"]!-cost)
        let reopened=try TradingEngine(context:rig.context,repository:rig.repo,initial:rig.repo.load()!)
        _=try await reopened.advance(to:1020,context:rig.context)
        _=try await rig.engine.advance(to:1020,context:rig.context)
        #expect(try AccountRepository.encode(await reopened.snapshot())==AccountRepository.encode(await rig.engine.snapshot()))
        _=try await rig.engine.advance(to:1020,context:rig.context)
        #expect(await rig.engine.snapshot().lifecycle?.carry.count==2)
    }
}
@Test func offlineDailyAndFinalSettlementAreAtomicAcrossRestart()async throws{
    let rig=try ScheduleRig(future:true);try await rig.open(.buy)
    let entry=try #require(await rig.engine.snapshot().positions[rig.instrument.id]?.average)
    var pending=OrderRequest(instrumentID:rig.instrument.id,side:.buy,kind:.limit,quantity:.one,price:try Amount("1"));pending.requestID="expires-with-contract"
    _=try await rig.engine.submit(pending,time:1000,context:rig.context)
    _=try await rig.engine.advance(to:1025,context:rig.context)
    let checkpoint=try #require(try rig.repo.fullSnapshot())
    #expect(checkpoint.events.filter{$0.kind=="futureSettlement"}.count==1)
    #expect(try checkpoint.positions[rig.instrument.id]?.average==Simulation.price(rig.instrument,at:1015,state:checkpoint.simulation!))
    let otherRoot=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),otherRepo=try AccountRepository(root:otherRoot,mode:.offline)
    let clone=try TradingEngine(context:rig.context,repository:otherRepo,initial:checkpoint)
    _=try await rig.engine.advance(to:1035,context:rig.context);_=try await clone.advance(to:1035,context:rig.context)
    let final=await rig.engine.snapshot()
    #expect(try AccountRepository.encode(final)==AccountRepository.encode(await clone.snapshot()))
    #expect(final.positions[rig.instrument.id]?.quantity == .zero)
    #expect(final.orders[pending.requestID]?.status == .expired);#expect(final.orders[pending.requestID]?.reserved == .zero)
    let finalPrice=try Simulation.price(rig.instrument,at:1030,state:final.simulation!),pnl=try (finalPrice-entry)*Amount("2")*Amount("3")
    #expect(try final.cash["TWD"]==Amount("100000")+pnl)
    #expect(final.events.filter{$0.kind=="futureSettlement"}.count==2)
}

@Test func offlineDailySettlementResolvesMissingDSTTimeOnce()async throws{
    let start=Int64(ISO8601DateFormatter().date(from:"2026-03-08T06:59:50Z")!.timeIntervalSince1970)
    let rig=try ScheduleRig(future:true,time:start,zone:"America/New_York",minute:150,expiry:start+86400)
    try await rig.open(.buy)
    _=try await rig.engine.advance(to:start+20,context:rig.context)
    let events=await rig.engine.snapshot().events.filter{$0.kind=="futureSettlement"}
    #expect(events.count==1);#expect(events.first?.time==start+10)
}
