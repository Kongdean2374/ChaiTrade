import Foundation

/// Presentation statistics only. No ledger or risk decision reads these Double values.
public struct EquityMetrics:Codable,Sendable{
    public var unit:Double?=1
    public var lastValue:Amount?
    public var lastTime:Int64?
    public var peak:Double=0
    public var drawdown:Double?
    public var segment=0
    public var hasGap=false
    public init(){}
    public var plottedUnit:Double?{lastValue==nil ? nil:unit}
    @discardableResult public mutating func consume(_ point:EquityPoint)->Double?{
        if let lastTime,point.time<lastTime{hasGap=true;segment+=1}
        lastTime=point.time
        let prior=lastValue;lastValue=point.value
        guard let value=point.value?.displayDouble else{hasGap=true;segment+=1;return nil}
        guard var valueUnit=unit else{return nil}
        if let prior{
            guard prior > .zero else{unit=nil;hasGap=true;return nil}
            valueUnit *= (value-point.flow.displayDouble)/prior.displayDouble
        }else{guard value>0 else{unit=nil;hasGap=true;return nil}}
        guard valueUnit.isFinite else{unit=nil;hasGap=true;return nil}
        unit=valueUnit==0 ? 0:valueUnit
        peak=max(peak,valueUnit)
        if peak>0{let next=(peak-valueUnit)/peak;if next.isFinite{drawdown=max(drawdown ?? 0,next)}else{hasGap=true}}
        return unit
    }
}
public struct EquityPageRow:Sendable,Identifiable{
    public let cursor:Int64
    public let point:EquityPoint
    public let metrics:EquityMetrics
    public var id:Int64{cursor}
}
