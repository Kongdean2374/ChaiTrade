import Foundation
import Testing
@testable import ChaiTradeCore

private func utc(_ text:String)->Int64{Int64(ISO8601DateFormatter().date(from:text)!.timeIntervalSince1970)}
@Test func optimizedCandlesExactlyMatchEveryAuthoritativeFiveSecondPrice()throws{
    let i=try #require(Simulation.catalog().first{$0.asset == .crypto})
    var s=SimulationState();s.time+=12345
    s.changes=[SimulationChange(time:s.time-7200+35,scenario:"恐慌",volatility:2.7,liquidity:1)]
    s.priceAdjustments=[PriceAdjustment(instrumentID:i.id,time:s.time-3600+20,factor:try Amount("0.5"))]
    let candles=try Simulation.candles(i,state:s,interval:3600,count:3)
    for c in candles{
        var values:[Double]=[],t=c.time
        while t<=min(c.time+3595,s.time){values.append(try Simulation.price(i,at:t,state:s).displayDouble);t+=5}
        #expect(c.open==values.first);#expect(c.close==values.last);#expect(c.high==values.max());#expect(c.low==values.min())
        #expect(c.volume==Double(values.count*i.liquidity))
    }
}
@Test func exchangeCalendarHandlesDSTWeeksAndLeapMonths(){
    let day=utc("2026-03-08T05:00:00Z")
    #expect(CandleCalendar.next(day,interval:86400,zone:"America/New_York")-day==23*3600)
    #expect(CandleCalendar.start(utc("2026-10-28T12:00:00Z"),interval:604800,zone:"Asia/Taipei")==utc("2026-10-25T16:00:00Z"))
    let feb=utc("2024-02-01T00:00:00Z")
    #expect(CandleCalendar.next(feb,interval:2592000,zone:"UTC")==utc("2024-03-01T00:00:00Z"))
    #expect(CandleCalendar.next(feb,interval:2592000,zone:"UTC")-feb==29*86400)
}
@Test func dailyWeeklyAndMonthlyHistoryShareTheSamePath()throws{
    let i=try #require(Simulation.catalog().first{$0.asset == .crypto}),s=SimulationState()
    let daily=try Simulation.candles(i,state:s,interval:86400,count:65)
    let weeks=try Simulation.candles(i,state:s,interval:604800,count:5)
    let expected=CandleCalendar.aggregate(daily,interval:604800,zone:"UTC",now:s.time)
    for c in weeks{let d=try #require(expected.first{$0.time==c.time});#expect(c.open==d.open);#expect(c.close==d.close);#expect(c.high==d.high);#expect(c.low==d.low);#expect(c.volume==d.volume)}
    let months=try Simulation.candles(i,state:s,interval:2592000,count:2)
    let monthly=CandleCalendar.aggregate(daily,interval:2592000,zone:"UTC",now:s.time)
    for c in months{let d=try #require(monthly.first{$0.time==c.time});#expect(c.high==d.high);#expect(c.low==d.low);#expect(c.volume==d.volume)}
    Simulation.clearChartCache()
    #expect(try Simulation.candles(i,state:s,interval:2592000,count:2).map(\.close)==months.map(\.close))
}
private actor PagedCandles:MarketTransport{
    var calls=0
    func get(_ url:URL,headers:[String:String])async throws->Data{
        calls+=1
        let q=Dictionary(uniqueKeysWithValues:URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.map{($0.name,$0.value!)})
        let end=utc(q["end"]!),step=Int64(q["granularity"]!)!,last=end/step*step
        let rows=(0..<300).map{[Double(last-Int64($0)*step),99,101,100,100,12]}
        return try JSONSerialization.data(withJSONObject:rows)
    }
    func count()->Int{calls}
}
@Test func providerHistoryPagesBackwardsAndAggregatesOnlyUpwards()async throws{
    let transport=PagedCandles(),i=try #require(Providers.catalog().first{$0.provider == .coinbase})
    let service=MarketDataProvider(id:.coinbase,credentials:ProviderCredentials(),transport:transport),now=utc("2026-10-27T12:00:00Z")
    let page=try await service.history(i,interval:1800,count:400,now:now)
    #expect(page.count==400);#expect(Set(page.map(\.time)).count==400)
    #expect(page.first!.time<now-300*900);#expect(await transport.count()>=3)
    #expect(page.dropLast().allSatisfy{$0.open==100 && $0.high==101 && $0.low==99 && $0.volume==24})
    #expect(page.last?.complete==false)
    let older=try await service.history(i,interval:1800,count:10,now:now,before:page.first!.time-1)
    #expect(older.last!.time<page.first!.time)
}

@Test func offlineStockHistoryPagesAcrossClosuresAndWeekends()throws{
    let instrument=try #require(Simulation.catalog().first{$0.asset == .taiwanStock}),state=SimulationState()
    let first=try Simulation.candles(instrument,state:state,interval:60,count:160)
    #expect(first.count==160)
    #expect(first.allSatisfy{instrument.rules.isOpen(at:$0.time)})
    #expect(first.first!.time<CandleCalendar.start(state.time,interval:86400,zone:instrument.rules.timeZone))
    let older=try Simulation.candles(instrument,state:state,interval:60,count:160,before:first.first!.time-1)
    #expect(older.count==160);#expect(older.last!.time<first.first!.time)
    #expect(Set((older+first).map(\.time)).count==320)
    #expect(older.allSatisfy{instrument.rules.isOpen(at:$0.time)})
}
