import Foundation
import Testing
@testable import ChaiTradeCore

private struct ContractRig{
    let context=AccountContext(mode:.online)
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let instrument:Instrument
    let repository:AccountRepository
    let engine:TradingEngine
    init(future:Bool=false,tiers:Bool=false)throws{
        var rules=try RulePack(tick:Amount("0.01"),quantityStep:.one);rules.maxLeverage=20;rules.fees.taker=try Amount("0.001")
        if tiers{rules.riskTiers=[RiskTier(upperNotional:try Amount(1000),initialRate:try Amount("0.1"),maintenanceRate:try Amount("0.05"),maxLeverage:10),RiskTier(upperNotional:nil,initialRate:try Amount("0.2"),maintenanceRate:try Amount("0.08"),maxLeverage:5)]}
        instrument=Instrument(id:"TEST:CONTRACT",symbol:"TEST",name:"合成合約風險驗證",asset:future ? .future:.perpetual,currency:"USD",rules:rules,initialPrice:try Amount(100))
        var initial=try TradingEngine.initial(mode:.online,baseCurrency:"USD",capital:Amount(10000),time:1000);initial.instruments=[instrument];initial.leverageEnabled=true
        repository=try AccountRepository(root:root,mode:.online);engine=try TradingEngine(context:context,repository:repository,initial:initial)
    }
    func quote(mark:String="100",sequence:Int64=1000)throws->Quote{
        var q=Quote(instrumentID:instrument.id,source:"synthetic-risk-fixture",time:sequence,sequence:sequence,last:try Amount(mark),bids:[Level(try Amount(99),try Amount(1000))],asks:[Level(try Amount(100),try Amount(1000))]);q.mark=try Amount(mark);return q
    }
    func request(side:Side,positionSide:PositionSide?,quantity:Int=5,reduce:Bool=false,leverage:Int=10)throws->OrderRequest{
        var request=OrderRequest(instrumentID:instrument.id,side:side,kind:.market,quantity:try Amount(quantity));request.positionSide=positionSide;request.reduceOnly=reduce;request.leverage=leverage;return request
    }
}
@Test func marginAdjustmentIntentAppliesOnceAndInvalidRemovalDoesNotConsumeItsID()async throws{
    let rig=try ContractRig(),context=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:context)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:nil),time:1000,context:context)
    let before=await rig.engine.snapshot(),original=try #require(before.positions[rig.instrument.id]?.margin)
    for _ in 0..<4{try await rig.engine.adjustMargin(instrumentID:rig.instrument.id,amount:Amount(20),time:1000,eventID:"stable-margin-adjustment",context:context)}
    let once=await rig.engine.snapshot();#expect(try once.positions[rig.instrument.id]?.margin==original+Amount(20));#expect(once.cash==before.cash)
    #expect(once.events.filter{$0.id=="stable-margin-adjustment"}.count==1)
    let next=AccountContext(mode:.online),reopened=try TradingEngine(context:next,repository:rig.repository,initial:#require(try rig.repository.load()))
    try await reopened.adjustMargin(instrumentID:rig.instrument.id,amount:Amount(20),time:1001,eventID:"stable-margin-adjustment",context:next)
    #expect(await reopened.snapshot().positions[rig.instrument.id]?.margin==once.positions[rig.instrument.id]?.margin)
    await #expect(throws:TradeError.self){try await reopened.adjustMargin(instrumentID:rig.instrument.id,amount:Amount(-1000),time:1001,eventID:"retry-after-invalid",context:next)}
    #expect(await reopened.snapshot().appliedEvents.contains("retry-after-invalid")==false)
    try await reopened.adjustMargin(instrumentID:rig.instrument.id,amount:Amount(1),time:1001,eventID:"retry-after-invalid",context:next)
    #expect(try await reopened.snapshot().positions[rig.instrument.id]?.margin==original+Amount(21))
}
@Test func marginWarningPrecedesLiquidationDoesNotRepeatAcrossRestartAndRearmsAfterRecovery()async throws{
    let r=try ContractRig(tiers:true),ctx=r.context
    try await r.engine.ingest(r.quote(),now:1000,context:ctx)
    _=try await r.engine.submit(r.request(side:.buy,positionSide:nil,leverage:5),time:1000,context:ctx)
    try await r.engine.ingest(r.quote(mark:"86",sequence:1001),now:1001,context:ctx)
    var full=try await r.engine.fullSnapshot(context:ctx)
    #expect(full.events.filter{$0.kind=="marginRisk"}.count==1);#expect(full.events.allSatisfy{$0.kind != "liquidation"})
    let next=AccountContext(mode:.online),reopened=try TradingEngine(context:next,repository:r.repository,initial:#require(try r.repository.load()))
    try await reopened.ingest(r.quote(mark:"85",sequence:1002),now:1002,context:next)
    #expect(try await reopened.fullSnapshot(context:next).events.filter{$0.kind=="marginRisk"}.count==1)
    try await reopened.ingest(r.quote(mark:"100",sequence:1003),now:1003,context:next)
    try await reopened.ingest(r.quote(mark:"86",sequence:1004),now:1004,context:next)
    #expect(try await reopened.fullSnapshot(context:next).events.filter{$0.kind=="marginRisk"}.count==2)
    try await reopened.ingest(r.quote(mark:"84",sequence:1005),now:1005,context:next)
    full=try await reopened.fullSnapshot(context:next)
    #expect(full.events.filter{$0.kind=="liquidation"}.count==1)
    #expect(full.inbox?.filter{$0.event.kind=="marginRisk"}.count==3)
    #expect(full.heldPositions(r.instrument.id).isEmpty)
}
@Test func hedgeSidesCloseIndependentlyAndLiquidationHasOnePermanentOrderAndFill()async throws{
    let rig=try ContractRig(tiers:true),ctx=rig.context
    try await rig.engine.setPositionMode(.hedge,context:ctx);try await rig.engine.ingest(rig.quote(),now:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:.long),time:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.sell,positionSide:.short),time:1000,context:ctx)
    var state=await rig.engine.snapshot()
    #expect(state.positions["TEST:CONTRACT::long"]?.quantity == (try Amount(5)))
    #expect(state.positions["TEST:CONTRACT::short"]?.quantity == (try Amount(-5)))
    #expect(state.heldPositions(rig.instrument.id).count==2)
    await #expect(throws:TradeError.self){try await rig.engine.setPositionMode(.oneWay,context:ctx)}
    await #expect(throws:TradeError.self){try await rig.engine.submit(rig.request(side:.buy,positionSide:nil),time:1000,context:ctx)}
    await #expect(throws:TradeError.self){try await rig.engine.submit(rig.request(side:.sell,positionSide:.long,quantity:6,reduce:true),time:1000,context:ctx)}
    _=try await rig.engine.submit(rig.request(side:.sell,positionSide:.long,quantity:2,reduce:true),time:1000,context:ctx)
    state=await rig.engine.snapshot();#expect(state.positions["TEST:CONTRACT::long"]?.quantity == (try Amount(3)));#expect(state.positions["TEST:CONTRACT::short"]?.quantity == (try Amount(-5)))
    let adverse=try rig.quote(mark:"120",sequence:1005);try await rig.engine.ingest(adverse,now:1005,context:ctx)
    state=await rig.engine.snapshot()
    #expect(state.positions["TEST:CONTRACT::long"]?.quantity == (try Amount(3)));#expect(state.positions["TEST:CONTRACT::short"]?.quantity == .zero)
    let fills=state.fills.filter{$0.modelVersion=="mark-liquidation-2"}
    #expect(fills.count==1)
    let fill=try #require(fills.first),order=try #require(state.orders[fill.orderID])
    #expect(order.status == .filled && order.request.reduceOnly && order.request.positionSide == .short)
    #expect(fill.positionKey=="TEST:CONTRACT::short" && fill.estimatedExecution && fill.source.contains("本機標記價強平模型"))
    #expect(fill.multiplier == .one);#expect(fill.notional == (try Amount(600)));#expect(fill.fee == (try Amount("0.6")))
    let cash=state.cash,ids=state.fills.map(\.id)
    try await rig.engine.ingest(adverse,now:1005,context:ctx)
    #expect(await rig.engine.snapshot().cash==cash);#expect(await rig.engine.snapshot().fills.map(\.id)==ids)
    let next=AccountContext(mode:.online),loaded=try rig.repository.load()!
    let restarted=try TradingEngine(context:next,repository:AccountRepository(root:rig.root,mode:.online),initial:loaded)
    #expect(await restarted.snapshot().positions["TEST:CONTRACT::long"]?.quantity == (try Amount(3)))
    #expect(await restarted.snapshot().positions["TEST:CONTRACT::short"]?.quantity == .zero)
}
@Test func hedgeFundingChargesAndCreditsEachSideExactlyOnceAndFutureSettlementKeepsBothSides()async throws{
    let rig=try ContractRig(future:true),ctx=rig.context
    try await rig.engine.setPositionMode(.hedge,context:ctx);try await rig.engine.ingest(rig.quote(),now:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:.long),time:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.sell,positionSide:.short),time:1000,context:ctx)
    let before=await rig.engine.snapshot()
    try await rig.engine.applyCarry(instrumentID:rig.instrument.id,rate:Amount("0.01"),mark:Amount(100),time:1000,eventID:"funding-two-sides",kind:"funding",source:"合成風險測試",context:ctx)
    var state=await rig.engine.snapshot()
    #expect(state.cash==before.cash);#expect(state.lifecycle?.carry.count==2)
    #expect(Set(state.lifecycle?.carry.compactMap(\.positionKey) ?? []).count==2)
    try await rig.engine.applyCarry(instrumentID:rig.instrument.id,rate:Amount("0.01"),mark:Amount(100),time:1000,eventID:"funding-two-sides",kind:"funding",source:"合成風險測試",context:ctx)
    #expect(await rig.engine.snapshot().lifecycle?.carry.count==2)
    try await rig.engine.settleFuture(instrumentID:rig.instrument.id,price:Amount(110),time:1000,eventID:"daily-hedge",final:false,context:ctx)
    state=await rig.engine.snapshot();#expect(state.heldPositions(rig.instrument.id).count==2)
    #expect(state.positions["TEST:CONTRACT::long"]?.average == (try Amount(110)));#expect(state.positions["TEST:CONTRACT::short"]?.average == (try Amount(110)))
    #expect(state.cash["USD"] == (try before.cash["USD"]!-Amount(5)))
    try await rig.engine.settleFuture(instrumentID:rig.instrument.id,price:Amount(105),time:1000,eventID:"final-hedge",final:true,context:ctx)
    #expect(await rig.engine.snapshot().heldPositions(rig.instrument.id).isEmpty)
}
@Test func progressiveMaintenanceIsContinuousAndNewOrdersRespectResultingTier()async throws{
    let rig=try ContractRig(tiers:true),rules=rig.instrument.rules,ctx=rig.context
    #expect(try rules.maintenanceMargin(notional:Amount(999))==Amount("49.95"))
    #expect(try rules.maintenanceMargin(notional:Amount(1000))==Amount(50))
    #expect(try rules.maintenanceMargin(notional:Amount(1001))==Amount("50.08"))
    #expect(try rules.initialMargin(notional:Amount(1001),leverage:10)==Amount("200.2"))
    try await rig.engine.ingest(rig.quote(),now:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:nil,quantity:5),time:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:nil,quantity:4),time:1000,context:ctx)
    await #expect(throws:TradeError.self){try await rig.engine.submit(rig.request(side:.buy,positionSide:nil,quantity:2),time:1000,context:ctx)}
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:nil,quantity:2,leverage:5),time:1000,context:ctx)
    #expect(await rig.engine.snapshot().positions[rig.instrument.id]?.margin == (try Amount(220)))
}

@Test func riskPreviewMatchesEngineAndNeverUsesStaleOrOtherCurrencyCollateral()async throws{
    let rig=try ContractRig(tiers:true),ctx=rig.context
    try await rig.engine.ingest(rig.quote(),now:1000,context:ctx)
    _=try await rig.engine.submit(rig.request(side:.buy,positionSide:nil),time:1000,context:ctx)
    let state=await rig.engine.snapshot(),risk=try ContractRisk.evaluate(state,positionKey:rig.instrument.id,now:1000)
    #expect(risk.collateral == (try Amount(50)));#expect(risk.maintenanceAndClosingFee == (try Amount("25.5")))
    let estimate=try ContractRisk.liquidationEstimate(state,positionKey:rig.instrument.id,now:1000)
    let lower=try #require(estimate.lower)
    let oneHundred=try Amount(100)
    #expect(lower > .zero && lower < oneHundred);#expect(estimate.upper==nil)
    #expect(throws:TradeError.self){try ContractRisk.evaluate(state,positionKey:rig.instrument.id,now:1100)}
    let below=try rig.quote(mark:(lower-Amount("0.02")).description,sequence:1005)
    try await rig.engine.ingest(below,now:1005,context:ctx)
    #expect(await rig.engine.snapshot().positions[rig.instrument.id]?.quantity == .zero)
}

@Test func marginWithdrawalRequiresFreshRiskIncludingCollateralFactorAndCloseFee()async throws{
    let rig=try ContractRig(tiers:true)
    try await rig.engine.ingest(rig.quote(),now:1000,context:rig.context)
    var request=try rig.request(side:.buy,positionSide:nil,quantity:5,leverage:10);request.marginMode = .isolated
    _=try await rig.engine.submit(request,time:1000,context:rig.context)
    let before=await rig.engine.snapshot(),position=try #require(before.positions[rig.instrument.id])
    // 500 notional, maintenance25 + closing fee0.5: removing25 from50 must fail.
    await #expect(throws:TradeError.self){try await rig.engine.adjustMargin(instrumentID:rig.instrument.id,amount:Amount("-25"),time:1000,context:rig.context)}
    #expect(await rig.engine.snapshot().positions[rig.instrument.id]?.margin==position.margin)
    await #expect(throws:TradeError.self){try await rig.engine.adjustMargin(instrumentID:rig.instrument.id,amount:Amount("-1"),time:1100,context:rig.context)}
    try await rig.engine.adjustMargin(instrumentID:rig.instrument.id,amount:Amount("10"),time:1100,context:rig.context)
    #expect(try await rig.engine.snapshot().positions[rig.instrument.id]?.margin==position.margin+Amount("10"))
    #expect(await rig.engine.snapshot().cash==before.cash)
}
