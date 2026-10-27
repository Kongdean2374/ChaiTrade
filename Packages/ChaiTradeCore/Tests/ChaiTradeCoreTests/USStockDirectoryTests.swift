import Foundation
import Testing
@testable import ChaiTradeCore

private let nasdaqDirectory="""
Symbol|Security Name|Market Category|Test Issue|Financial Status|Round Lot Size|ETF|NextShares
AAPL|Apple Inc. - Common Stock|Q|N|N|40|N|N
QQQ|Invesco QQQ Trust ETF|G|N|N|100|Y|N
FAKE|Synthetic Test Common Stock|Q|Y|N|100|N|N
TESTW|Test Warrant|Q|N|N|100|N|N
File Creation Time: 1027202618:00|||||||
"""
private let otherDirectory="""
ACT Symbol|Security Name|Exchange|CQS Symbol|ETF|Round Lot Size|Test Issue|NASDAQ Symbol
SPY|SPDR S&P 500 ETF Trust|P|SPY|Y|100|N|SPY
BRK.B|Berkshire Hathaway Class B Common Stock|N|BRK/B|N|100|N|BRK.B
File Creation Time: 1027202618:00|||||||
"""
private actor DirectoryTransport:MarketTransport{
    private(set) var calls=0
    func get(_ url:URL,headers:[String:String])async throws->Data{
        calls+=1;#expect(headers.isEmpty)
        return Data((url.lastPathComponent=="nasdaqlisted.txt" ? nasdaqDirectory:otherDirectory).utf8)
    }
}
@Test func officialDirectoryPreservesNamesVenueClassesAndPagination()async throws{
    let transport=DirectoryTransport(),directory=try USStockDirectory(mode:.online,transport:transport)
    let all=try await directory.search("",limit:2)
    #expect(all.total==4);#expect(all.instruments.count==2)
    #expect(all.instruments.first?.symbol=="AAPL");#expect(all.instruments.first?.identity?.boardLot==40)
    let next=try await directory.search("",offset:2,limit:2)
    #expect(Set((all.instruments+next.instruments).map(\.id)).count==4)
    let spy=try #require(try await directory.search("SPY").instruments.first)
    #expect(spy.asset == .etf);#expect(spy.name=="SPDR S&P 500 ETF Trust");#expect(spy.identity?.exchange=="NYSE ARCA");#expect(spy.currency=="USD")
    #expect(spy.initialPrice == .zero);#expect(spy.provider == .alpaca)
    let brk=try #require(try await directory.search("Berkshire").instruments.first)
    #expect(brk.symbol=="BRK.B");#expect(brk.identity?.exchange=="NYSE")
    #expect(NetworkPolicy.permits(URL(string:"https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt")!,method:"GET",mode:.online))
    #expect(!NetworkPolicy.permits(URL(string:"https://www.nasdaqtrader.com/trade")!,method:"POST",mode:.online))
    let before=await transport.calls
    #expect(throws:TradeError.self){try USStockDirectory(mode:.offline,transport:transport)}
    #expect(await transport.calls==before)
    #expect(throws:TradeError.self){try USStockDirectory.parse(nasdaq:Data("invalid".utf8),other:Data(otherDirectory.utf8),query:"")}
    let ambiguous=otherDirectory.replacingOccurrences(of:"SPY|SPDR",with:"AAPL|SPDR")
    #expect(throws:TradeError.self){try USStockDirectory.parse(nasdaq:Data(nasdaqDirectory.utf8),other:Data(ambiguous.utf8),query:"")}
}
@Test(.enabled(if:ProcessInfo.processInfo.environment["CHAI_LIVE"]=="1"))
func liveOfficialUSDirectorySearchIsMetadataAndNotAFabricatedQuote()async throws{
    let directory=try USStockDirectory(mode:.online,transport:ReadOnlyTransport(mode:.online))
    for symbol in ["AAPL","SPY"]{
        let result=try await directory.search(symbol),product=try #require(result.instruments.first)
        #expect(product.symbol==symbol);#expect(!product.name.contains("待核對"));#expect(product.identity?.exchange != nil)
        #expect(product.asset == (symbol=="SPY" ? .etf:.usStock));#expect(product.initialPrice == .zero)
    }
    print("LIVE_US_DIRECTORY_HTTP_SUCCESS: public official identity metadata; no market prices inferred.")
}
