import Foundation

public enum AlertPriceBasis:String,Codable,CaseIterable,Sendable{
    case creationPrice,sourceReference
    public var label:String{self == .creationPrice ? "建立時價格":"來源前收／24小時起價（建立時固定）"}
}
/// A notification carries account and canonical event identity only. Never trust a supplied product/order.
public struct NoticeLink:Codable,Equatable,Sendable,Identifiable{
    public let accountID:String
    public let eventID:String
    public var id:String{accountID+"."+eventID}
    public var mode:Mode{Mode.allCases.first{$0.accountID==accountID}!}
    public init(accountID:String,eventID:String)throws{
        guard Mode.allCases.contains(where:{$0.accountID==accountID}),!eventID.isEmpty,eventID.count<=256,!eventID.unicodeScalars.contains(where:{$0.value<32}) else{throw TradeError.invalid("通知連結身份無效")}
        self.accountID=accountID;self.eventID=eventID
    }
    public init(from decoder:Decoder)throws{
        let box=try decoder.container(keyedBy:CodingKeys.self)
        try self.init(accountID:box.decode(String.self,forKey:.accountID),eventID:box.decode(String.self,forKey:.eventID))
    }
}
public struct NoticeDestination:Sendable,Identifiable{
    public var event:AuditEvent
    public var instrument:Instrument?
    public var opensOrders:Bool{event.orderID != nil}
    public var id:String{event.id}
}
