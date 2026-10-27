import Foundation
import Testing
@testable import ChaiTradeCore

@Test func participantPoolsArePersistentAndRefillAtDistinctCadences()throws{
    var state=try TradingEngine.initial(mode:.offline,capital:Amount("100000"),time:0)
    let instrument=try #require(state.instruments.first{$0.symbol=="BTC-USD"})
    state.simulation!.time=1_800_000_000;state.simulation!.participantsFrom=state.simulation!.time-60
    let first=try Simulation.quote(instrument,state:state.simulation!)
    state.simulation!.time+=5
    let second=try Simulation.quote(instrument,state:state.simulation!)
    #expect(first.asks.count>8)
    #expect(Set(first.asks.compactMap(\.participant)).count>=3)
    #expect(first.asks.map(\.liquidityID)==second.asks.map(\.liquidityID))
    let used=try #require(first.asks.first)
    let usage=[used.liquidityID!:ParticipantUsage(quantity:used.quantity,expiresAt:used.liquidityExpiresAt!)]
    let remaining=try SimulationParticipants.displayLevels(second.asks,usage:usage)
    #expect(try sum(remaining.map(\.quantity))==sum(second.asks.map(\.quantity))-used.quantity)
    state.simulation!.time+=5
    let third=try Simulation.quote(instrument,state:state.simulation!)
    #expect(Set(first.asks.filter{$0.participant=="participants-1-1"}.compactMap(\.liquidityID))==Set(third.asks.filter{$0.participant=="participants-1-1"}.compactMap(\.liquidityID)))
    #expect(Set(first.asks.filter{$0.participant=="participants-1-0"}.compactMap(\.liquidityID)) != Set(third.asks.filter{$0.participant=="participants-1-0"}.compactMap(\.liquidityID)))
}
@Test func ownTradeImpactIsArchivedCausalAndReplaysAfterPruningAndRestart()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.offline)
    var initial=try TradingEngine.initial(mode:.offline,baseCurrency:"USD",capital:Amount("10000000"),time:0)
    let instrument=try #require(initial.instruments.first{$0.symbol=="BTC-USD"})
    initial.instruments=[instrument];initial.simulation!.newsFrom=nil;initial.simulation!.newsAccountingFrom=nil
    let start=initial.simulation!.time
    let repository=try AccountRepository(root:root,mode:.offline),engine=try TradingEngine(context:context,repository:repository,initial:initial)
    try await engine.initializeQuotes(context:context)
    let request=OrderRequest(instrumentID:instrument.id,side:.buy,kind:.market,quantity:try Amount("0.1"))
    _=try await engine.submit(request,time:start,context:context)
    let firstIntent=await engine.snapshot()
    _=try await engine.submit(request,time:start,context:context)
    let filled=await engine.snapshot(),fill=try #require(filled.fills.first),impact=try #require(fill.simulationImpact)
    #expect(filled.orders.count==1);#expect(filled.fills.map(\.id)==firstIntent.fills.map(\.id));#expect(filled.cash==firstIntent.cash);#expect(filled.participantUsage==firstIntent.participantUsage)
    #expect(try sum(filled.fills.map(\.quantity))==Amount("0.1"));#expect(filled.participantUsage?.count==filled.fills.count)
    #expect(fill.liquidityEventID.hasPrefix("participants-1|"));#expect(fill.generatedEventIDs==[impact.groupID])
    #expect(try Simulation.price(instrument,at:start,state:filled.simulation!)==Simulation.price(instrument,at:start,state:initial.simulation!))
    #expect(try Simulation.price(instrument,at:start+35,state:filled.simulation!)>Simulation.price(instrument,at:start+35,state:initial.simulation!))
    #expect(Simulation.stepVolume(instrument,at:start,state:filled.simulation!)>Simulation.stepVolume(instrument,at:start,state:initial.simulation!))
    var future=filled.simulation!;future.time=start+35
    #expect(try Simulation.quote(instrument,state:future).causalEventIDs?.contains(impact.groupID)==true)
    while await engine.snapshot().simulation!.time<start+600{_=try await engine.advance(to:start+600,context:context)}
    let pruned=await engine.snapshot()
    #expect(pruned.simulation!.impactGroups?.isEmpty==true);#expect(pruned.participantUsage?.isEmpty==true)
    #expect(throws:SimulationHistoryError.self){try Simulation.price(instrument,at:start+35,state:pruned.simulation!)}
    let full=try await engine.fullSnapshot(context:context)
    let expected=try Simulation.candles(instrument,state:full.simulation!,interval:60,count:11)
    let restarted=try TradingEngine(context:context,repository:AccountRepository(root:root,mode:.offline),initial:repository.load()!)
    try await restarted.initializeQuotes(context:context)
    let actual=try await restarted.simulationCandles(instrumentID:instrument.id,interval:60,count:11,context:context)
    #expect(actual==expected)
    let restored=try TradingEngine(context:context,repository:AccountRepository(root:root.appendingPathComponent("restored"),mode:.offline),initial:full)
    #expect(await restored.snapshot().simulation!.impactGroups?.isEmpty==true)
    #expect(try await restored.simulationCandles(instrumentID:instrument.id,interval:60,count:11,context:context)==expected)
    #expect(actual.first?.volume != nil)
    #expect(try await restarted.fullSnapshot(context:context).fills.count==filled.fills.count)
}
@Test func impactAggregationUsesExactCommutativeAmounts()throws{
    let a=SimulationImpact(groupID:"same",instrumentID:"SIM:TEST",volumeTime:0,startsAt:5,endsAt:305,amplitude:try Amount("0.000000000001"),volume:try Amount("0.01"))
    var b=a;b.amplitude=try Amount("-0.000000000002");b.volume=try Amount("0.02")
    #expect(try SimulationParticipants.grouped([a,b,a])==SimulationParticipants.grouped([b,a,a]))
    #expect(try SimulationParticipants.grouped([a,b,a]).first?.amplitude == .zero)
}

@Test func lazySimulationBooksStillProcessOrdersAndPositionsWithoutVisibleDemand()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.offline)
    var state=try TradingEngine.initial(mode:.offline,baseCurrency:"USD",capital:Amount("1000000"),time:0)
    let btc=try #require(state.instruments.first{$0.symbol=="BTC-USD"}),eth=try #require(state.instruments.first{$0.symbol=="ETH-USD"})
    state.instruments=[btc,eth];state.simulation!.newsFrom=nil;state.simulation!.newsAccountingFrom=nil
    let engine=try TradingEngine(context:context,repository:AccountRepository(root:root,mode:.offline),initial:state)
    try await engine.initializeQuotes(fullBookIDs:[btc.id],context:context)
    #expect(await engine.snapshot().quotes[btc.id]?.grade == .E1);#expect(await engine.snapshot().quotes[eth.id]?.grade == .E0)
    _=try await engine.submit(OrderRequest(instrumentID:btc.id,side:.buy,kind:.market,quantity:try Amount("0.01")),time:state.simulation!.time,context:context)
    try await engine.setSimulationDemand([],context:context)
    _=try await engine.advance(to:state.simulation!.time+5,context:context)
    let next=await engine.snapshot()
    #expect(next.quotes[btc.id]?.grade == .E1);#expect(next.quotes[eth.id]?.grade == .E0)
    #expect(next.quotes[eth.id]?.last ?? .zero > .zero)
    try await engine.setSimulationDemand([eth.id],context:context)
    #expect(await engine.snapshot().quotes[eth.id]?.grade == .E1)
    #expect(await engine.snapshot().cash==next.cash)
}
