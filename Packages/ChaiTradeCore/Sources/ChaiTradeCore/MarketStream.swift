import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OrderBookTracker: Sendable {
    public private(set) var sequence: Int64 = -1
    public private(set) var valid = false
    private var buy: [Amount:Amount] = [:]
    private var sell: [Amount:Amount] = [:]
    public init() {}
    public var bids: [Level] { buy.map{Level($0.key,$0.value)}.sorted{$0.price>$1.price} }
    public var asks: [Level] { sell.map{Level($0.key,$0.value)}.sorted{$0.price<$1.price} }
    public mutating func invalidate() { valid=false }
    public mutating func snapshot(bids: [Level],asks: [Level],sequence: Int64) throws {
        guard sequence>=0,Set(bids.map(\.price)).count==bids.count,Set(asks.map(\.price)).count==asks.count,
              (bids+asks).allSatisfy({$0.price > .zero && $0.quantity > .zero}) else {valid=false;throw TradeError.unavailable("委託簿快照不合法")}
        buy=Dictionary(uniqueKeysWithValues:bids.map{($0.price,$0.quantity)});sell=Dictionary(uniqueKeysWithValues:asks.map{($0.price,$0.quantity)})
        self.sequence=sequence;valid=true;try validate()
    }
    /// Sequence policies are explicit: Coinbase full channels require contiguous IDs; Binance futures use pu.
    public mutating func delta(bids: [Level],asks: [Level],sequence: Int64,previousSequence: Int64?,contiguous: Bool) throws {
        guard valid else{throw TradeError.unavailable("委託簿需先建立有效快照")}
        if sequence<=self.sequence{return}
        guard (previousSequence == nil || previousSequence==self.sequence),(!contiguous || sequence==self.sequence+1) else{valid=false;throw TradeError.unavailable("深度序列漏包；暫停成交並重新建立快照")}
        guard (bids+asks).allSatisfy({$0.price > .zero && $0.quantity >= .zero}) else{valid=false;throw TradeError.unavailable("深度增量不合法")}
        for l in bids{if l.quantity == .zero{buy.removeValue(forKey:l.price)}else{buy[l.price]=l.quantity}}
        for l in asks{if l.quantity == .zero{sell.removeValue(forKey:l.price)}else{sell[l.price]=l.quantity}}
        self.sequence=sequence;try validate()
    }
    private mutating func validate() throws {
        guard let bid=buy.keys.max(),let ask=sell.keys.min(),bid<ask else{valid=false;throw TradeError.unavailable("深度缺少雙邊或交叉盤，等待重建")}
    }
}

/// Public Coinbase Exchange level2/ticker stream. No authentication or order messages are sent.
public struct CoinbaseMarketStream: Sendable {
    public init(mode: Mode) throws {guard mode == .online else{throw TradeError.invalid("B 禁止建立 WebSocket")}}
    public func quotes(instrument: Instrument) throws -> AsyncThrowingStream<Quote,Error> {
        guard instrument.provider == .coinbase,instrument.symbol.range(of:#"^[A-Z0-9]+-[A-Z0-9]+$"#,options:.regularExpression) != nil else{throw TradeError.invalid("WebSocket 商品不合法")}
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=30;configuration.timeoutIntervalForResource=86400
        let session=URLSession(configuration:configuration,delegate:RedirectBlocker(),delegateQueue:nil)
        let url=URL(string:"wss://ws-feed.exchange.coinbase.com")!
        guard NetworkPolicy.permitsWebSocket(url,mode:.online) else{throw TradeError.invalid("WebSocket 主機不在白名單")}
        let socket=session.webSocketTask(with:url)
        return AsyncThrowingStream(bufferingPolicy:.bufferingOldest(512)){continuation in
            let task=Task {
                socket.resume()
                let heartbeat=Task {
                    while !Task.isCancelled {
                        do{try await Task.sleep(for:.seconds(20));try await socket.sendPing()}catch{socket.cancel(with:.goingAway,reason:nil);break}
                    }
                }
                defer{heartbeat.cancel();socket.cancel(with:.goingAway,reason:nil);session.invalidateAndCancel()}
                do{
                    let subscription:[String:Any]=["type":"subscribe","product_ids":[instrument.symbol],"channels":["level2","ticker","heartbeat"]]
                    let data=try JSONSerialization.data(withJSONObject:subscription)
                    try await socket.send(.data(data))
                    var book=OrderBookTracker(),last: Amount?,sourceTime: Int64=0,ordinal: Int64=0
                    let connectionID=UUID().uuidString
                    while !Task.isCancelled {
                        let message=try await socket.receive(),data: Data
                        switch message{case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:throw TradeError.unavailable("未知 WebSocket 格式")}
                        guard data.count<=2_000_000 else{throw TradeError.unavailable("WebSocket 訊息過大")}
                        let json=try JSONValue.parse(data)
                        let type=json["type"].string ?? ""
                        if type=="error"{throw TradeError.unavailable("Coinbase WebSocket 拒絕訂閱；請核對服務可用性／頻道權限")}
                        guard json["product_id"].string==instrument.symbol else{continue}
                        ordinal+=1
                        let now=Int64(Date().timeIntervalSince1970)
                        if let text=json["time"].string{
                            let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
                            if let date=f.date(from:text){sourceTime=Int64(date.timeIntervalSince1970)}
                        }
                        if type=="snapshot"{
                            try book.snapshot(bids:json["bids"].array.map{try Level($0[0].amount(),$0[1].amount())},asks:json["asks"].array.map{try Level($0[0].amount(),$0[1].amount())},sequence:ordinal)
                        }else if type=="l2update"{
                            var bids:[Level]=[],asks:[Level]=[]
                            for row in json["changes"].array{
                                let level=try Level(row[1].amount(),row[2].amount())
                                guard row[0].string=="buy" || row[0].string=="sell" else{throw TradeError.unavailable("深度方向欄位變更")}
                                if row[0].string=="buy"{bids.append(level)}else{asks.append(level)}
                            }
                            // Coinbase level2 is an ordered snapshot/change stream, not the full channel's sequence protocol.
                            // A new connection always requires a fresh snapshot; no ticker sequence gaps are treated as L2 gaps.
                            try book.delta(bids:bids,asks:asks,sequence:ordinal,previousSequence:nil,contiguous:false)
                        }else if type=="ticker"{last=try json["price"].amount()}
                        else{continue}
                        guard book.valid,let last,sourceTime>0 else{continue}
                        let q=Quote(instrumentID:instrument.id,source:"Coinbase Exchange WS \(connectionID)",time:sourceTime,sequence:ordinal,last:last,bids:Array(book.bids.prefix(50)),asks:Array(book.asks.prefix(50)),coverage:"Coinbase level2；本機影子流動性，非真實排隊順位",receivedAt:now)
                        if case .dropped=continuation.yield(q){throw TradeError.unavailable("行情處理落後，已停用深度並要求重新同步")}
                    }
                    continuation.finish()
                }catch{continuation.finish(throwing:TradeError.unavailable("Coinbase 連線中斷或訂閱失敗；深度已停用，將退避重連"))}
            }
            continuation.onTermination={_ in task.cancel();socket.cancel(with:.goingAway,reason:nil)}
        }
    }
}

extension NetworkPolicy {
    public static func permitsWebSocket(_ url: URL,mode: Mode) -> Bool {
        mode == .online && url.scheme=="wss" && url.host=="ws-feed.exchange.coinbase.com" && (url.path.isEmpty || url.path=="/") && url.query==nil && url.user==nil && url.password==nil && (url.port==nil || url.port==443)
    }
}
