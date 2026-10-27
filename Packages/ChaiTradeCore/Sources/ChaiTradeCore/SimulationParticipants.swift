import Foundation

public struct ParticipantUsage:Codable,Equatable,Sendable{
    public var quantity:Amount
    public var expiresAt:Int64
}
public struct SimulationImpact:Codable,Equatable,Sendable{
    public var groupID:String
    public var instrumentID:String
    public var volumeTime:Int64
    public var startsAt:Int64
    public var endsAt:Int64
    public var amplitude:Amount
    public var volume:Amount
}
public enum SimulationHistoryError:Error,LocalizedError{
    case needsArchivedImpacts
    public var errorDescription:String?{"這段歷史需要載入已歸檔的交易衝擊，請重新載入圖表。"}
}
public enum SimulationParticipants{
    public static func displayLevels(_ levels:[Level],usage:[String:ParticipantUsage]?)throws->[Level]{
        var values:[Amount:Amount]=[:],order:[Amount]=[]
        for level in levels{
            let available=max(.zero,try level.quantity-(level.liquidityID.flatMap{usage?[$0]?.quantity} ?? .zero))
            if available == .zero{continue}
            if values[level.price]==nil{order.append(level.price)}
            values[level.price]=try (values[level.price] ?? .zero)+available
        }
        return order.map{Level($0,values[$0]!)}
    }

    public static let model="participants-1"
    private static let periods:[Int64]=[10,30,60,20]
    private static let shares=[45,30,20,5]
    public static func levels(_ instrument:Instrument,state:SimulationState,board:TradingBoard?,side:Side,price:Amount,spread:Amount,count:Int)throws->[Level]{
        let enabled=state.participantsFrom ?? Int64.max
        var result:[Level]=[]
        let control=state.changes.last{$0.time<=state.time}?.time ?? 0
        let news=SimulationNews.active(instrument,at:state.time,state:state).map(\.id).sorted().joined(separator:",")
        for profile in periods.indices{
            let period=periods[profile],birth=max(enabled,state.time/period*period)
            let direction=Simulation.random(seed:state.seed,stream:Simulation.hash(instrument.id)&+UInt64(profile+1700),index:birth/period)>0.5
            if profile==3 && (side == .buy) != direction{continue}
            let anchor=try Simulation.price(instrument,at:birth,state:state)
            for depth in 1...8{
                var units=max(0,count*shares[profile]/100/depth)
                if instrument.usesTaiwanBoards,board != .oddLot{
                    let lot=instrument.identity?.boardLot ?? 1000
                    units=units/lot*lot
                    if profile==0 && depth==1 && units==0 && count>=lot{units=lot}
                }
                if units==0{continue}
                var size=try instrument.rules.quantityStep*Amount(units)
                if instrument.usesTaiwanBoards,board == .oddLot{size=min(try Amount(999),size)}
                let distance=try spread*Amount(depth+(profile==2 ? 1:0))
                let tick=instrument.rules.tick(at:price)
                let raw=side == .buy ? max(tick,min(try anchor-distance,try price-tick)):max(try anchor+distance,try price+tick)
                let levelPrice=try instrument.rules.roundedPrice(raw,side == .buy ? .down:.up)
                let id="\(model)|\(instrument.id)|\(board?.rawValue ?? "default")|\(side.rawValue)|\(profile)|\(depth)|\(birth)|\(control)|\(news)"
                var level=Level(levelPrice,size);level.liquidityID=id;level.liquidityExpiresAt=birth+period;level.participant="\(model)-\(profile)"
                result.append(level)
            }
        }
        return result.sorted{a,b in a.price==b.price ? (a.liquidityID ?? "")<(b.liquidityID ?? ""):side == .buy ? a.price>b.price:a.price<b.price}
    }
    public static func impact(instrument:Instrument,quantity:Amount,side:Side,quote:Quote,time:Int64)throws->SimulationImpact{
        let visible=try sum((side == .buy ? quote.asks:quote.bids).map(\.quantity))
        let fraction=visible > .zero ? min(1,(try quantity/visible).displayDouble):0
        let magnitude=min(0.03,fraction*0.01)*(side == .buy ? 1:-1)
        let amplitude=try Amount(String(format:"%.12f",locale:Locale(identifier:"en_US_POSIX"),magnitude))
        let start=time+Simulation.step
        return SimulationImpact(groupID:"impact-\(instrument.id)-\(time)",instrumentID:instrument.id,volumeTime:time,startsAt:start,endsAt:start+300,amplitude:amplitude,volume:quantity)
    }
    public static func grouped(_ impacts:[SimulationImpact])throws->[SimulationImpact]{
        var values:[String:SimulationImpact]=[:]
        for impact in impacts{if var old=values[impact.groupID]{old.amplitude=try old.amplitude+impact.amplitude;old.volume=try old.volume+impact.volume;values[impact.groupID]=old}else{values[impact.groupID]=impact}}
        return values.values.sorted{($0.volumeTime,$0.groupID)<($1.volumeTime,$1.groupID)}
    }
    public static func priceImpact(_ instrument:Instrument,at time:Int64,state:SimulationState)->Double{
        let value=(state.impactGroups ?? []).filter{$0.instrumentID==instrument.id && $0.startsAt<=time && time<$0.endsAt}.reduce(0.0){total,impact in
            let age=Double(time-impact.startsAt),remaining=Double(impact.endsAt-time)
            let kernel=max(0,min(1,age/30,remaining/270))
            return total+impact.amplitude.displayDouble*kernel
        }
        return 0.03*tanh(value/0.03)
    }
    public static func ownVolume(_ instrument:Instrument,at time:Int64,state:SimulationState)->Double{(state.impactGroups ?? []).filter{$0.instrumentID==instrument.id && $0.volumeTime==time}.reduce(0){$0+$1.volume.displayDouble}}
}
