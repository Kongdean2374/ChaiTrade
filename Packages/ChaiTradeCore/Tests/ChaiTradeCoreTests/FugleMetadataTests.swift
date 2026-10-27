import Foundation
import Testing
@testable import ChaiTradeCore

private actor MetadataTransport: MarketTransport {
    let securityCode: String
    let variant: String
    private var reads=0
    init(code:String="01",variant:String="normal"){securityCode=code;self.variant=variant}
    func count()->Int{reads}
    func get(_ url:URL,headers:[String:String])async throws->Data{
        reads+=1
        #expect(url.path=="/marketdata/v1.0/stock/intraday/ticker/2330")
        var data:[String:Any]=["date":"2026-10-27","type":"EQUITY","symbol":"2330","name":"合成協定測試資料",
            "exchange":"TWSE","market":"TSE","securityType":securityCode,"boardLot":1000,"tradingCurrency":"TWD",
            "industry":"00","securityStatus":"NORMAL","matchingInterval":0,"isDisposition":false,"canDayTrade":true,
            "referencePrice":100,"limitUpPrice":110,"limitDownPrice":90]
        switch variant{
        case "wrongSymbol":data["symbol"]="2454"
        case "wrongExchange":data["exchange"]="TPEx";data["market"]="OTC"
        case "inconsistentMarket":data["market"]="OTC"
        case "missingCurrency":data.removeValue(forKey:"tradingCurrency")
        case "missingLot":data.removeValue(forKey:"boardLot")
        case "foreignETF":data["tradingCurrency"]="USD";data["boardLot"]=100
        case "futureDate":data["date"]="2026-10-28"
        case "badDate":data["date"]="2026-02-30"
        case "suspended":data["securityStatus"]="SUSPENDED"
        case "disposition":data["isDisposition"]=true;data["matchingInterval"]=300
        case "badLimits":data["limitDownPrice"]=120
        default:break
        }
        return try JSONSerialization.data(withJSONObject:data)
    }
}
private func metadataProvider(_ transport:MetadataTransport,key:String="synthetic-fixture-not-a-key")->MarketDataProvider{
    MarketDataProvider(id:.fugle,credentials:ProviderCredentials(key:key),transport:transport)
}
private func metadataStock()throws->Instrument{try #require(InstrumentCatalog.builtIn(mode:.online).first{$0.symbol=="2330"})}
private let metadataNow:Int64=1_793_064_600

@Test(arguments:["01","24","32","47","37","00"])
func fugleSecurityTypesNeverInferETFFromIndustryZero(code:String)async throws{
    let metadata=try await metadataProvider(MetadataTransport(code:code)).securityMetadata(metadataStock(),now:metadataNow)
    let expected:TaiwanSecurityClassification=code=="01" ? .stock:code=="24" ? .etf:["32","47"].contains(code) ? .bondETF:code=="00" ? .unknown:.other
    #expect(metadata.classification==expected)
    #expect(metadata.symbol=="2330" && metadata.exchange=="TWSE")
    if [TaiwanSecurityClassification.other,.unknown].contains(expected){#expect(metadata.classification.assetClass==nil);#expect(metadata.restriction != nil)}
}
@Test func fugleVerifiedMetadataUsesSourceCurrencyUnitAndKeepsTradingRulesUnverified()async throws{
    let original=try metadataStock()
    let metadata=try await metadataProvider(MetadataTransport(code:"25",variant:"foreignETF")).securityMetadata(original,now:metadataNow)
    #expect(metadata.currency=="USD" && metadata.boardLot==100 && metadata.classification == .etf)
    let candidate=try metadata.resolvedCandidate(original)
    #expect(candidate.id==original.id && candidate.symbol==original.symbol)
    #expect(candidate.currency=="USD" && candidate.identity?.boardLot==100 && candidate.asset == .etf)
    #expect(candidate.requiresRuleConfirmation==true)
    #expect(original.currency=="TWD" && original.asset == .taiwanStock && original.identity?.boardLot==1000)
}
@Test(arguments:["wrongSymbol","wrongExchange","inconsistentMarket","missingCurrency","missingLot","futureDate","badDate","badLimits"])
func fugleMalformedOrMismatchedMetadataIsRejectedBeforeAccountChanges(variant:String)async throws{
    do{_ = try await metadataProvider(MetadataTransport(variant:variant)).securityMetadata(metadataStock(),now:metadataNow);Issue.record("invalid metadata accepted")}
    catch let failure as MarketDataFailure{#expect(failure.kind == .invalidData)}
}
@Test func fugleSourceTradingRestrictionsAreExplicitAndMetadataNeedsAKey()async throws{
    let stock=try metadataStock()
    let suspended=try await metadataProvider(MetadataTransport(variant:"suspended")).securityMetadata(stock,now:metadataNow)
    #expect(suspended.isSuspended && suspended.restriction != nil)
    #expect(try suspended.resolvedCandidate(stock).halted)
    let disposition=try await metadataProvider(MetadataTransport(variant:"disposition")).securityMetadata(stock,now:metadataNow)
    #expect(disposition.matchingInterval==300 && disposition.isDisposition==true && disposition.restriction != nil)
    let transport=MetadataTransport()
    do{_ = try await metadataProvider(transport,key:"").securityMetadata(stock,now:metadataNow);Issue.record("missing key accepted")}
    catch let failure as MarketDataFailure{#expect(failure.kind == .missingKey)}
    #expect(await transport.count()==0)
    let url=try #require(URL(string:"https://api.fugle.tw/marketdata/v1.0/stock/intraday/ticker/2330"))
    #expect(NetworkPolicy.permits(url,method:"GET",mode:.online))
    #expect(!NetworkPolicy.permits(url,method:"GET",mode:.offline))
    #expect(!NetworkPolicy.permits(url,method:"POST",mode:.online))
}
@Test func everyBuiltInTaiwanFutureKeepsCanonicalIdentityWithItsExactHistoryProduct()throws{
    let all=try InstrumentCatalog.builtIn(mode:.online).filter{$0.provider == .fugleFutures}
    #expect(all.count>=4)
    for instrument in all{
        let before=instrument.id,resolved=try FugleContract.resolve(instrument)
        #expect(resolved.month=="202611" && instrument.id==before)
        if instrument.symbol=="TE202611"{#expect(resolved.product=="EXF")}
        if instrument.symbol=="TF202611"{#expect(resolved.product=="FXF")}
    }
}
