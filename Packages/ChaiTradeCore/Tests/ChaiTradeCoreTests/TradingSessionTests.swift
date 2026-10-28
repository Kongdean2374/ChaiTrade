import Foundation
import Testing
@testable import ChaiTradeCore

private func sessionTime(_ iso:String)throws->Int64{Int64(try #require(ISO8601DateFormatter().date(from:iso)).timeIntervalSince1970)}
@Test func initialQuoteAndEnrichedSummaryKeepTheSamePriorCloseAcrossHolidaysWeekendsAndHalfDays()throws{
    let catalog=try InstrumentCatalog.builtIn(mode:.offline)
    // Fixed published session boundaries, independent of the summary helper.
    for (symbol,now,previous,last) in [
        ("2330","2026-10-27T01:30:00Z","2026-10-23T05:29:55Z","2026-10-27T01:30:00Z"),
        ("2330","2026-11-02T01:30:00Z","2026-10-30T05:29:55Z","2026-11-02T01:30:00Z"),
        ("2330","2026-10-31T04:00:00Z","2026-10-30T05:29:55Z","2026-10-30T05:29:55Z"),
        ("AAPL","2026-11-02T15:00:00Z","2026-10-30T19:59:55Z","2026-11-02T15:00:00Z"),
        ("AAPL","2026-11-30T15:00:00Z","2026-11-27T17:59:55Z","2026-11-30T15:00:00Z")
    ]{
        let instrument=try #require(catalog.first{$0.symbol==symbol})
        var simulation=SimulationState();simulation.time=try sessionTime(now)
        let boundary=try sessionTime(previous),reference=try Simulation.price(instrument,at:boundary,state:simulation)
        let initial=try Simulation.quote(instrument,state:simulation,includeBook:false)
        let detail=try Simulation.quote(instrument,state:simulation,includeBook:true)
        let enriched=try Simulation.summary(instrument,state:simulation)
        #expect(initial.summary?.reference==reference)
        #expect(detail.summary?.reference==reference)
        #expect(enriched.reference==reference)
        #expect(initial.last==detail.last)
        #expect(try initial.last==Simulation.price(instrument,at:sessionTime(last),state:simulation))
        // Archived event/impact replay must include the actual reference day,
        // which can be more than 24 hours before a Monday/holiday opening.
        #expect(try Simulation.quoteHistoryStart(instrument,state:simulation)<=boundary)
        #expect(try Simulation.summaryHistoryStart(instrument,state:simulation)<=boundary)
    }
    for symbol in ["BTC-USD","BTCUSDT","EUR/USD"]{
        let instrument=try #require(catalog.first{$0.symbol==symbol})
        var simulation=SimulationState();simulation.time=try sessionTime("2026-11-02T15:00:00Z")
        let reference=try Simulation.price(instrument,at:simulation.time-86400,state:simulation)
        #expect(try Simulation.quote(instrument,state:simulation).summary?.reference==reference)
        #expect(try Simulation.summary(instrument,state:simulation).reference==reference)
    }
}
@Test func cmeAndReferenceFXRespectSundayStartsFridayCloseAndDailyMaintenanceAcrossDST()throws{
    let catalog=try InstrumentCatalog.builtIn(mode:.offline),cme=try #require(catalog.first{$0.symbol=="ESZ6"}),fx=try #require(catalog.first{$0.symbol=="EUR/USD"})
    for time in ["2026-10-25T22:00:00Z","2026-11-01T23:00:00Z","2026-10-30T20:59:55Z"]{#expect(try cme.rules.isOpen(at:sessionTime(time)))}
    for time in ["2026-10-25T21:59:55Z","2026-11-01T22:59:55Z","2026-10-30T21:00:00Z","2026-10-31T12:00:00Z","2026-10-27T21:30:00Z"]{#expect(try !cme.rules.isOpen(at:sessionTime(time)))}
    for time in ["2026-10-25T21:05:00Z","2026-11-01T22:05:00Z","2026-10-30T20:58:55Z"]{#expect(try fx.rules.isOpen(at:sessionTime(time)))}
    for time in ["2026-10-25T21:04:55Z","2026-11-01T22:04:55Z","2026-10-30T20:59:00Z","2026-10-27T21:00:00Z"]{#expect(try !fx.rules.isOpen(at:sessionTime(time)))}
    var invalid=fx.rules;invalid.sessionOverrides=["2026-02-31":[]]
    #expect(throws:TradeError.self){try TradingSessions.validate(invalid)}
}
@Test func tradingClosuresDoNotEraseSettlementOnlyBusinessDays()throws{
    let stock=try #require(InstrumentCatalog.builtIn(mode:.offline).first{$0.symbol=="2330"})
    let trade=try sessionTime("2026-02-11T01:30:00Z"),settlement=try MarketCalendar.settlementDate(tradeTime:trade,businessDays:2,rules:stock.rules)
    #expect(stock.rules.isOpen(at:trade));#expect(try !stock.rules.isOpen(at:sessionTime("2026-02-12T01:30:00Z")))
    #expect(try settlement==sessionTime("2026-02-13T01:30:00Z"))
    #expect(try !stock.rules.isOpen(at:sessionTime("2026-10-26T01:30:00Z")))
    #expect(stock.rules.calendarYears==[2026])
}
@Test func usHalfDaysAndPreviousCloseUseThePublishedSessionBoundary()throws{
    let stock=try #require(InstrumentCatalog.builtIn(mode:.offline).first{$0.symbol=="AAPL"})
    #expect(try stock.rules.isOpen(at:sessionTime("2026-11-27T17:59:55Z")))
    #expect(try !stock.rules.isOpen(at:sessionTime("2026-11-27T18:00:00Z")))
    #expect(try TradingSessions.previousOpen(before:sessionTime("2026-11-27T22:00:00Z"),rules:stock.rules)==sessionTime("2026-11-27T17:59:55Z"))
    #expect(try !stock.rules.isOpen(at:sessionTime("2026-11-26T17:00:00Z")))
}
@Test func fridayNightSessionContinuesOnSaturdayButSundayNightDoesNotOpen()throws{
    let future=try #require(InstrumentCatalog.builtIn(mode:.offline).first{$0.symbol=="TXF202611"})
    for time in ["2026-10-30T15:59:55Z","2026-10-30T17:00:00Z","2026-10-30T20:59:55Z"]{#expect(try future.rules.isOpen(at:sessionTime(time)))}
    for time in ["2026-10-30T21:00:00Z","2026-11-01T17:00:00Z","2026-11-02T06:00:00Z"]{#expect(try !future.rules.isOpen(at:sessionTime(time)))}
    #expect(try future.rules.isOpen(at:sessionTime("2026-11-02T07:00:00Z")))
    #expect(try TradingSessions.previousOpen(before:sessionTime("2026-10-31T12:00:00Z"),rules:future.rules)==sessionTime("2026-10-30T20:59:55Z"))
}
@Test func sessionBoundsUseRealDSTElapsedTimeAndRepeatedHourPolicy()throws{
    var rules=try RulePack(tick:Amount("0.01"),quantityStep:.one);rules.timeZone="America/New_York";rules.sessions=[TradingSession(openMinute:90,closeMinute:210,weekdays:[1])]
    for (day,duration) in [("2026-03-08T16:00:00Z",Int64(3600)),("2026-11-01T16:00:00Z",Int64(10800))]{
        let date=Date(timeIntervalSince1970:TimeInterval(try sessionTime(day))),bounds=try #require(TradingSessions.intervals(anchorDay:date,rules:rules).first)
        #expect(bounds.end-bounds.start==duration)
        #expect(rules.isOpen(at:bounds.start));#expect(rules.isOpen(at:bounds.end-5));#expect(!rules.isOpen(at:bounds.end))
    }
}
@Test func overnightCandlesAndSummaryExactlyCountActualOpenSteps()throws{
    let instrument=try #require(InstrumentCatalog.builtIn(mode:.offline).first{$0.symbol=="TXF202611"})
    var simulation=SimulationState();simulation.time=try sessionTime("2026-10-30T17:15:00Z")
    let candles=try Simulation.candles(instrument,state:simulation,interval:60,count:4)
    #expect(candles.count==4)
    for candle in candles{
        let through=min(simulation.time,candle.time+55),points=try stride(from:candle.time,through:through,by:5).map{try Simulation.price(instrument,at:$0,state:simulation).displayDouble}
        #expect(candle.open==points.first);#expect(candle.close==points.last);#expect(candle.high==points.max());#expect(candle.low==points.min())
        #expect(candle.volume==Double(points.count*instrument.liquidity))
    }
    let summary=try Simulation.summary(instrument,state:simulation)
    let start=try sessionTime("2026-10-30T16:00:00Z")
    #expect(summary.volume?.displayDouble==Double((simulation.time-start)/5+1)*Double(instrument.liquidity))
}
@Test func futuresSourceIdentityIsSeparateFromSavedPositionIdentity()throws{
    for (symbol,source) in [("TXF202611","TXFK6"),("MXF202611","MXFK6"),("TE202611","EXFK6"),("TF202611","FXFK6")]{
        let future=try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol==symbol})
        #expect(future.sourceSymbol==source);#expect(future.id=="fugleFutures:"+symbol)
        #expect(try future.rules.expiry==sessionTime("2026-11-18T05:30:00Z"))
        #expect(future.requiresRuleConfirmation==true)
    }
    var invalid=try RulePack(tick:Amount("0.01"),quantityStep:.one);invalid.sessions=[TradingSession(openMinute:1500,closeMinute:100)]
    #expect(throws:TradeError.self){try TradingSessions.validate(invalid)}
}
