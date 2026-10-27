import Foundation

public struct CarrySchedule:Codable,Equatable,Sendable{
    public var interval:Int64
    public var offset:Int64
    public var longRate:Amount
    public var shortRate:Amount
    public var kind:String
    public init(interval:Int64=28800,offset:Int64=0,longRate:Amount,shortRate:Amount,kind:String="funding"){
        self.interval=interval;self.offset=offset;self.longRate=longRate;self.shortRate=shortRate;self.kind=kind
    }
}

public struct PriceAdjustment: Codable, Sendable {
    public var instrumentID: String
    public var time: Int64
    public var factor: Amount
}
public struct SettlementEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var currency: String
    public var due: Int64
    public var receivable: Amount
    public var payable: Amount
    public var completedAt: Int64?
}
public enum CorporateActionKind: String, Codable, CaseIterable, Sendable { case split, dividend, rename, halt, resume, cashLiquidation }
public struct CorporateAction: Codable, Identifiable, Sendable {
    public var id: String
    public var instrumentID: String
    public var kind: CorporateActionKind
    public var time: Int64
    public var ratio: Amount?
    public var cashPerUnit: Amount?
    public var paymentTime: Int64?
    public var newSymbol: String?
    public var source: String
    public init(id: String = UUID().uuidString, instrumentID: String, kind: CorporateActionKind, time: Int64, ratio: Amount? = nil, cashPerUnit: Amount? = nil, paymentTime: Int64? = nil, newSymbol: String? = nil, source: String) {
        self.id=id;self.instrumentID=instrumentID;self.kind=kind;self.time=time;self.ratio=ratio;self.cashPerUnit=cashPerUnit;self.paymentTime=paymentTime;self.newSymbol=newSymbol;self.source=source
    }
}
public struct CarryEvent: Codable, Identifiable, Sendable {
    public var id: String
    public var instrumentID: String
    public var time: Int64
    public var rate: Amount
    public var mark: Amount
    public var amount: Amount
    public var kind: String
    public var source: String
    public var calculationModel:String?
}
public struct LifecycleState: Codable, Sendable {
    public var settlements: [SettlementEvent] = []
    public var actions: [CorporateAction] = []
    public var carry: [CarryEvent] = []
    public var rates: [FXRate] = []
    public init() {}
}
public enum MarketCalendar {
    public static func settlementDate(tradeTime: Int64, businessDays: Int, rules: RulePack) throws -> Int64 {
        guard businessDays >= 0,businessDays <= 10,let zone=TimeZone(identifier:rules.timeZone) else { throw TradeError.invalid("交割規則不合法") }
        var c=Calendar(identifier:.gregorian);c.timeZone=zone
        var date=Date(timeIntervalSince1970:TimeInterval(tradeTime));var remaining=businessDays
        let f=DateFormatter();f.timeZone=zone;f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd"
        while remaining>0 {
            guard let next=c.date(byAdding:.day,value:1,to:date) else { throw TradeError.invalid("交割日期超出範圍") };date=next
            let weekday=c.component(.weekday,from:date)
            if weekday != 1 && weekday != 7 && !rules.holidays.contains(f.string(from:date)){remaining-=1}
        }
        return Int64(date.timeIntervalSince1970)
    }
}
