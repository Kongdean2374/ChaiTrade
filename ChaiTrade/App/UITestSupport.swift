import SwiftUI
import ChaiTradeCore

// Compiled out of the distributed Release app. Each XCTest owns a new directory;
// relaunching within that test deliberately reuses its UUID for persistence checks.
#if DEBUG
@MainActor enum UITestSupport {
    static var session: String? {
        let args=ProcessInfo.processInfo.arguments
        guard args.contains("--uitest"),let index=args.firstIndex(of:"--uitest-session"),args.indices.contains(index+1),let uuid=UUID(uuidString:args[index+1]) else{return nil}
        return uuid.uuidString
    }
    static var fixture:Bool { session != nil && ProcessInfo.processInfo.arguments.contains("--uitest-fixture") }
    static var contention:Bool { fixture && ProcessInfo.processInfo.arguments.contains("--uitest-contention") }
    static var controlledCatchup:Bool { fixture && ProcessInfo.processInfo.arguments.contains("--uitest-controlled-catchup") }
    static func root(base:URL)->URL{
        guard let session else{return base.appendingPathComponent("ChaiTrade",isDirectory:true)}
        return base.appendingPathComponent("ChaiTradeUITests/\(session)",isDirectory:true)
    }
    static func prepare(root:URL)throws{
        if fixture,!FileManager.default.fileExists(atPath:root.appendingPathComponent("app-settings.json").path){
            var settings=AppSettings();settings.activeMode = .offline;settings.onboarded=true
            for mode in Mode.allCases {
                var state=try TradingEngine.initial(mode:mode,capital:Amount("100000"),time:1_793_064_600)
                if mode == .offline{state.instruments=Array(state.instruments.filter{$0.asset == .taiwanStock}.prefix(2));state.simulation!.paused=true;state.continueWhileAway=false}
                let repo=try AccountRepository(root:root,mode:mode);try repo.save(state)
            }
            try settings.save(root:root)
        }
    }
    static func delay()async{if contention{let duration=ProcessInfo.processInfo.arguments.contains("--uitest-slow-save") ? 10000:2000;try? await Task.sleep(for:.milliseconds(duration))}}
    static func submissionDelay()async{if fixture && ProcessInfo.processInfo.arguments.contains("--uitest-slow-submit"){try? await Task.sleep(for:.seconds(10))}}
    static func checkpoint()async{if controlledCatchup{try? await Task.sleep(for:.milliseconds(700))}}
}
#endif

struct UITestProbe: View {
    @EnvironmentObject var model:AppModel
    var body:some View{
        #if DEBUG
        if let session=UITestSupport.session {
            Text(snapshot(session:session)).font(.system(size:1)).frame(width:1,height:1)
                .accessibilityIdentifier("uiTestState").accessibilityHidden(false)
        }
        #endif
    }
    #if DEBUG
    private func snapshot(session:String)->String{
        let s=model.state
        let fills=s?.fills ?? [],ids=Set(fills.map(\.id))
        let payload:[String:Any]=[
            "session":session,"ready":s != nil,"tab":model.tab,"selected":model.selectedID,
            "cash":s?.cash.mapValues(\.description) ?? [:],"watchlist":s?.watchlist.sorted() ?? [],
            "journals":s?.journals.map{["id":$0.id,"text":$0.text]} ?? [],
            "orders":s?.orders.keys.sorted() ?? [],
            "fills":fills.map{f -> [String:String] in ["id":f.id,"order":f.orderID,"quantity":f.quantity.description,"price":f.price.description,"fee":f.fee.description,"tax":f.tax.description,"multiplier":s?.instruments.first(where:{$0.id==f.instrumentID})?.rules.multiplier.description ?? "1"]},
            "positions":s?.positions.mapValues{$0.quantity.description} ?? [:],
            "fillCash":s?.ledger.filter{$0.account=="cash" && ids.contains($0.eventID)}.map{["event":$0.eventID,"amount":$0.amount.description]} ?? [],
            "operations":model.uiTestOperations,"mutationStarts":model.uiTestMutationStarts,"maxOperations":model.uiTestMaxOperations,"catchupNotices":s?.events.filter{$0.kind=="catchupComplete"}.count ?? 0,
            "catchup":model.progress != nil,"pendingCatchup":model.catchupTarget != nil,
            "chartTime":model.candles.last?.time ?? 0,"chartLoading":model.chartLoading,"time":s?.simulation?.time ?? 0
        ]
        guard let data=try? JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),let json=String(data:data,encoding:.utf8) else{return "{}"};return json
    }
    #endif
}

struct UITestCatchupControl:View {
    @EnvironmentObject var model:AppModel
    var body:some View{
        #if DEBUG
        if UITestSupport.controlledCatchup {
            Button("開始受控補算"){model.catchupTarget=model.now+10800;Task{await model.catchUp()}}
                .accessibilityIdentifier("uiTestBeginCatchup")
        }
        #endif
    }
}
