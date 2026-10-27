import Foundation
import Testing
@testable import ChaiTradeCore

private func interactionEngine()throws->(URL,AccountContext,TradingEngine){
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),context=AccountContext(mode:.online)
    var rules=RulePack(tick:try Amount("0.01"),quantityStep:.one);rules.fees.fixed=try Amount("2")
    let instrument=Instrument(id:"INTERACTION",symbol:"INTERACTION",name:"Synthetic interaction fixture",asset:.crypto,currency:"TWD",rules:rules,initialPrice:try Amount("100"))
    var initial=try TradingEngine.initial(mode:.online,capital:Amount("1000"),time:1000);var second=instrument;second.id="SECOND";second.symbol="SECOND";initial.instruments=[instrument,second]
    let repository=try AccountRepository(root:root,mode:.online)
    return (root,context,try TradingEngine(context:context,repository:repository,initial:initial))
}

@Test func concurrentDuplicateOrderIntentDebitsOnceAcrossRestart()async throws{
    let (root,context,engine)=try interactionEngine()
    let quote=Quote(instrumentID:"INTERACTION",source:"synthetic-concurrency-fixture",time:1000,sequence:1,last:try Amount("100"),bids:[Level(try Amount("99.99"),try Amount("1000"))],asks:[Level(try Amount("100"),try Amount("1000"))])
    try await engine.ingest(quote,now:1000,context:context)
    var intent=OrderRequest(instrumentID:"INTERACTION",side:.buy,kind:.market,quantity:.one);intent.requestID="one-confirmed-draft"
    let request=intent
    let ids=try await withThrowingTaskGroup(of:String.self){group in
        for _ in 0..<48{group.addTask{try await engine.submit(request,time:1000,context:context)}}
        var results=[String]();for try await id in group{results.append(id)};return results
    }
    #expect(ids.count==48);#expect(Set(ids)==[request.requestID])
    let state=try await engine.fullSnapshot(context:context)
    #expect(state.orders.count==1);#expect(state.fills.count==1)
    #expect(state.positions["INTERACTION"]?.quantity == .one)
    #expect(try state.cash["TWD"]==Amount("898"))
    let cash=state.ledger.filter{$0.account=="cash" && $0.eventID==state.fills[0].id}
    #expect(try cash.reduce(Amount.zero){try $0+$1.amount}==Amount("-102"))
    let restoredContext=AccountContext(mode:.online),repository=try AccountRepository(root:root,mode:.online)
    let restored=try TradingEngine(context:restoredContext,repository:repository,initial:repository.load()!)
    _=try await restored.submit(request,time:1000,context:restoredContext)
    #expect(await restored.snapshot().fills.count==1)
    #expect(try await restored.snapshot().cash["TWD"]==Amount("898"))
}

@Test func stableJournalDraftIdentityIsIdempotentButNewDraftCanRepeatText()async throws{
    let (root,context,engine)=try interactionEngine()
    let draft=JournalEntry(id:"stable-draft",text:"Synthetic repeated note",tags:"",time:1000)
    try await withThrowingTaskGroup(of:Void.self){group in
        for _ in 0..<32{group.addTask{try await engine.recordJournal(draft,context:context)}}
        try await group.waitForAll()
    }
    let once=await engine.snapshot();#expect(once.journals.count==1);#expect(once.journals.first?.id==draft.id)
    let next=JournalEntry(id:"new-intent-same-content",text:draft.text,tags:"",time:1001)
    try await engine.recordJournal(next,context:context)
    let repository=try AccountRepository(root:root,mode:.online),reopened=try repository.load()!
    #expect(reopened.journals.count==2);#expect(Set(reopened.journals.map(\.id))==[draft.id,next.id])
    await #expect(throws:TradeError.self){try await engine.recordJournal(next,context:AccountContext(mode:.online))}
    await #expect(throws:TradeError.self){try await engine.recordJournal(JournalEntry(text:" \n",tags:"",time:1002),context:context)}
    #expect(await engine.snapshot().journals.count==2)
}

@Test func concurrentFavoriteTogglesPreserveEveryIntentAndOtherInstruments()async throws{
    let (root,context,engine)=try interactionEngine()
    try await withThrowingTaskGroup(of:Void.self){group in
        for n in 0..<201{let id=n<100 ? "INTERACTION":"SECOND";group.addTask{try await engine.toggleWatch(id,context:context)}}
        try await group.waitForAll()
    }
    #expect(await engine.snapshot().watchlist==["SECOND"])
    let repository=try AccountRepository(root:root,mode:.online)
    #expect(try repository.load()?.watchlist==["SECOND"])
    await #expect(throws:TradeError.self){try await engine.toggleWatch("missing",context:context)}
    await #expect(throws:TradeError.self){try await engine.toggleWatch("SECOND",context:AccountContext(mode:.online))}
    #expect(await engine.snapshot().watchlist==["SECOND"])
}
