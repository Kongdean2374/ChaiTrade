import Foundation

/// A form identity includes the venue and contract kind, never just a ticker.
public struct TradeProduct:Codable,Equatable,Sendable {
    public var id:String
    public var exchange:String?
    public var asset:AssetClass
    public var currency:String
    public init(_ i:Instrument){id=i.id;exchange=i.identity?.exchange;asset=i.asset;currency=i.currency}
    public func matches(_ i:Instrument)->Bool{self == TradeProduct(i)}
}
public struct TradeEditor:Codable,Equatable,Sendable {
    public var side=Side.buy
    public var contractAction="openLong"
    public var kind=OrderKind.limit
    public var price="",quantity="1",unit="股",trigger="",distance="0.05"
    public var trailingPercent=true
    public var reference=TriggerReference.last
    public var tif=TimeInForce.GTC
    public var expiry:Int64=0
    public var postOnly=false,reduceOnly=false
    public var leverage=1
    public var margin=MarginMode.isolated
    public var protection="無",profit="",stop=""
    public var advanced=false
    public var requestID=UUID().uuidString,ocoRequestID=UUID().uuidString
    public init(){}
}
public struct TradeWorkspace:Codable,Equatable,Sendable {
    public var accountID:String
    public var product:TradeProduct
    public var side:Side
    public var board:TradingBoard
    public var revision:UInt64
    public var editor:TradeEditor?
    public init(accountID:String,instrument:Instrument,side:Side = .buy,revision:UInt64=1){
        self.accountID=accountID;product=TradeProduct(instrument);self.side=side;board=instrument.usesTaiwanBoards ? .oddLot:.regular;self.revision=revision
    }
    public func validate(in state:AccountState)throws{
        guard accountID==state.accountID,revision>0,let i=state.instruments.first(where:{$0.id==product.id}),product.matches(i),i.asset != .index else{throw TradeError.invalid("交易草稿的帳戶或商品身份不符")}
        if let e=editor{
            let strings=[e.price,e.quantity,e.unit,e.trigger,e.distance,e.protection,e.profit,e.stop,e.requestID,e.ocoRequestID,e.contractAction]
            guard strings.allSatisfy({$0.utf8.count<=256}),!e.requestID.isEmpty,!e.ocoRequestID.isEmpty,e.leverage>=1,e.leverage<=i.rules.maxLeverage else{throw TradeError.invalid("交易草稿內容不合法")}
        }
    }
}
