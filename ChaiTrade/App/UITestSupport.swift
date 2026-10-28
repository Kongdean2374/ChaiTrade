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
    private(set) static var favoriteBarrierArrivals=0
    private(set) static var favoriteBarrierFailed=false
    // Only this fixture synchronizes the first four distinct UI intents. A fixed
    // two-second sleep did not overlap the slower native pointer dispatches.
    // Real SQLite mutations still use the unmodified serial engine transaction.
    static func awaitFavoriteContention()async throws{
        guard fixture,ProcessInfo.processInfo.arguments.contains("--uitest-favorite-barrier"),favoriteBarrierArrivals<4 else{return}
        favoriteBarrierArrivals+=1
        let clock=ContinuousClock(),deadline=clock.now.advanced(by:.seconds(30))
        while favoriteBarrierArrivals<4{
            guard !favoriteBarrierFailed,clock.now<deadline else{favoriteBarrierFailed=true;throw TradeError.invalid("自選並發測試未收到四次獨立操作")}
            try await Task.sleep(for:.milliseconds(50))
        }
        guard !favoriteBarrierFailed else{throw TradeError.invalid("自選並發測試同步失敗")}
    }
    static func root(base:URL)->URL{
        guard let session else{return base.appendingPathComponent("ChaiTrade",isDirectory:true)}
        return base.appendingPathComponent("ChaiTradeUITests/\(session)",isDirectory:true)
    }
    static func prepare(root:URL)throws{
        if fixture,!FileManager.default.fileExists(atPath:root.appendingPathComponent("app-settings.json").path){
            var settings=AppSettings();settings.activeMode = .offline;settings.onboarded=true
            for mode in Mode.allCases {
                var state=try TradingEngine.initial(mode:mode,capital:Amount("100000"),time:1_793_064_600)
                if mode == .offline{if !ProcessInfo.processInfo.arguments.contains("--uitest-full-catalog"){state.instruments=Array(try Simulation.legacyCatalog().filter{$0.asset == .taiwanStock}.prefix(2))};state.simulation=SimulationState();state.simulation!.paused=true;state.continueWhileAway=false}
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

struct UITestVisualEnvironment:ViewModifier{
    func body(content:Content)->some View{
        #if DEBUG
        if UITestSupport.session != nil,ProcessInfo.processInfo.arguments.contains("--uitest-large-type"){content.dynamicTypeSize(.accessibility3)}else{content}
        #else
        content
        #endif
    }
}
struct UITestProbe: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
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
        var inspected=model.visibleQuoteIDs;inspected.insert(model.selectedID)
        var quoteStates:[String:String]=[:]
        for instrument in s?.instruments ?? [] where inspected.contains(instrument.id){quoteStates[instrument.id]=model.status(for:instrument).rawValue}
        let payload:[String:Any]=[
            "visualType":String(describing:typeSize),"visualTheme":colorScheme == .dark ? "dark":"light",
            "session":session,"ready":s != nil,"tab":model.tab,"selected":model.selectedID,
            "fileArchiveWorking":model.fileArchiveWorking,"fileArchiveReady":model.fileArchiveURL != nil,"fileArchiveProgress":model.fileArchiveProgress,
            "dataShareReady":model.dataShareURL != nil,"dataShareFormat":model.dataShareURL?.pathExtension ?? "",
            "quoteFocus":model.activeProductID ?? "",
            "tradeProduct":model.tradeWorkspace?.product.id ?? "","tradeSide":model.tradeWorkspace?.side.rawValue ?? "","tradeDraftQuantity":model.tradeWorkspace?.editor?.quantity ?? "","marketPath":model.marketPaths[model.market] ?? [],
            "appVersion":AppVersion.number,"appBuild":AppVersion.build,
            "mode":s?.mode.rawValue ?? "", "market":model.market.rawValue,"search":model.currentBrowsing.search,"category":model.currentBrowsing.category,"sort":model.currentBrowsing.sort.rawValue,
            "leverageEnabled":s?.leverageEnabled ?? false,
            "instruments":s?.instruments.map{["id":$0.id,"symbol":$0.symbol,"name":$0.name,"market":$0.market.rawValue]} ?? [],
            "quotes":s?.quotes.mapValues{["price":$0.last.description,"time":String($0.time),"valid":String($0.valid),"receivedAt":String($0.receivedAt),"quality":$0.quality.rawValue,"maximumAge":String($0.maximumAge)]} ?? [:],
            "quoteStates":quoteStates,"marketClock":model.marketClock,"foreground":model.foreground,"simulationPaused":s?.simulation?.paused ?? true,
            "news":model.filteredNews.map{["id":$0.id,"label":$0.label,"title":$0.title,"origin":$0.origin.rawValue]},

            "alerts":s?.alerts.map{["id":$0.id,"instrument":$0.instrumentID,"price":$0.price.description,"baseline":$0.baseline?.description ?? "","percentage":$0.percentage?.description ?? ""]} ?? [],
            "inbox":s?.inbox?.map{["account":$0.accountID,"event":$0.event.id,"kind":$0.event.kind]} ?? [],
            "cash":s?.cash.mapValues(\.description) ?? [:],"watchlist":s?.watchlist.sorted() ?? [],
            "journals":s?.journals.map{["id":$0.id,"text":$0.text]} ?? [],
            "orders":s?.orders.keys.sorted() ?? [],
            "orderIntents":s?.orders.values.map{["id":$0.id,"instrument":$0.request.instrumentID,"side":$0.request.side.rawValue,"kind":$0.request.kind.rawValue,"price":$0.request.price?.description ?? "","quantity":$0.request.quantity.description,"status":$0.status.rawValue,"reduceOnly":String($0.request.reduceOnly),"positionSide":$0.request.positionSide?.rawValue ?? ""]} ?? [],
            "fills":fills.map{f -> [String:String] in ["id":f.id,"order":f.orderID,"quantity":f.quantity.description,"price":f.price.description,"fee":f.fee.description,"tax":f.tax.description,"multiplier":s?.instruments.first(where:{$0.id==f.instrumentID})?.rules.multiplier.description ?? "1"]},
            "positions":s?.positions.mapValues{$0.quantity.description} ?? [:],
            "fillCash":s?.ledger.filter{$0.account=="cash" && ids.contains($0.eventID)}.map{["event":$0.eventID,"amount":$0.amount.description]} ?? [],
            "orderDismissRequests":model.uiTestOrderDismissRequests,"orderDismissDiagnostics":model.uiTestOrderDismissDiagnostics,
            "boardRequests":model.uiTestBoardRequests,"selectedBoard":model.selectedBoard.rawValue,"tradeWorkspaceBoard":model.tradeWorkspace?.board.rawValue ?? "","chartDiagnostics":model.uiTestChartDiagnostics,
            "operations":model.uiTestOperations,"mutationStarts":model.uiTestMutationStarts,"maxOperations":model.uiTestMaxOperations,"favoriteBarrierArrivals":UITestSupport.favoriteBarrierArrivals,"favoriteBarrierFailed":UITestSupport.favoriteBarrierFailed,"catchupNotices":s?.events.filter{$0.kind=="catchupComplete"}.count ?? 0,
            "marketTapRequests":model.uiTestMarketRequests,"productTapSelections":model.uiTestProductSelections,
            "catchup":model.progress != nil,"pendingCatchup":model.catchupTarget != nil,
            "chartTime":model.candles.last?.time ?? 0,"chartLoading":model.chartLoading,"time":s?.simulation?.time ?? 0,
            "chartRendered":Dictionary(uniqueKeysWithValues:model.chartRenderings.filter{$0.value.context==model.context && $0.value.instrumentID==model.selectedID && $0.value.interval==model.interval}.map{($0.key,$0.value.count)}),
            "receiptOrders":model.latestOrderReceipt?.context==model.context ? model.latestOrderReceipt?.orderIDs ?? []:[]
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
