import SwiftUI
import UIKit
import ChaiTradeCore

enum OrderSubmissionOutcome{case accepted,rejected(String)}

private struct OrderDraft:Identifiable{
    let id=UUID()
    let instrument:Instrument
    let context:AccountContext
    let side:Side
    let board:TradingBoard
    var closingPosition:Position?
    var workspaceSession:UUID?
}
struct TradingView:View{
    var browseInstrumentID:String?=nil
    @EnvironmentObject var model:AppModel
    @State private var choosingProduct=false
    @State private var pickerChoice:TradeHandoff?
    @State private var draft:OrderDraft?
    @State private var showOrdersAfterDismiss=false
    @State private var fullscreen=false
    @State private var details=false
    @State private var drawing=false
    @State private var alert=false
    @State private var connections=false
    @State private var contractAccess=false
    @State private var contractAccessSession=UUID()
    @State private var indicator="MA"
    @State private var period=20
    @State private var line=false
    private let intervals:[(String,Int64)]=[("1分",60),("5分",300),("15分",900),("30分",1800),("1時",3600),("4時",14400),("日",86400),("週",604800),("月",2592000)]
    private var instrument:Instrument?{if let id=browseInstrumentID{return model.state?.instruments.first{$0.id==id}};return model.tradeInstrument}
    private var quote:Quote?{guard let i=instrument else{return nil};return model.state?.quotes[i.quoteKey(board:i.usesTaiwanBoards ? model.selectedBoard:nil)]}
    private var active:Bool{browseInstrumentID == nil ? model.tab==2:model.tab==1 && model.marketPaths[model.market]?.last==browseInstrumentID}
    var body:some View{
        ScrollView{
            if browseInstrumentID==nil{tradeSelector}
            if let i=instrument{
                productContent(i)
            }else{ContentUnavailableView("先選擇商品",systemImage:"chart.xyaxis.line",description:Text("前往行情頁搜尋代碼或名稱"));Button("探索行情"){model.tab=1}}
        }.background(Color(.systemGroupedBackground)).navigationTitle(browseInstrumentID==nil ? "交易":"商品詳情").navigationBarTitleDisplayMode(.inline)
            .refreshable{await model.fetchQuotes()}
            .safeAreaInset(edge:.bottom){tradeBar}
            .sheet(item:$draft,onDismiss:{if showOrdersAfterDismiss{showOrdersAfterDismiss=false;model.tab=3}}){intent in NavigationStack{OrderForm(instrument:intent.instrument,accountContext:intent.context,initialSide:intent.side,initialBoard:intent.board,initialPosition:intent.closingPosition,workspaceSession:intent.workspaceSession,onCancelled:{guard draft?.id==intent.id else{return};showOrdersAfterDismiss=false;draft=nil},onSubmitted:{if let session=intent.workspaceSession{model.clearTradeEditor(session:session)};showOrdersAfterDismiss=true;draft=nil})}}
            .sheet(isPresented:$choosingProduct,onDismiss:applyPickerChoice){NavigationStack{TradeProductPicker(onSelection:{i in guard let context=model.context else{return};pickerChoice=TradeHandoff(product:TradeProduct(i),context:context,side:model.tradeWorkspace?.side ?? .buy,openForm:false,board:i.usesTaiwanBoards ? .oddLot:.regular,closingPosition:nil)})}.modifier(UITestVisualEnvironment())}
            .sheet(isPresented:$details){NavigationStack{InstrumentDetails()}}
            .sheet(isPresented:$drawing){NavigationStack{DrawingEditor()}}
            .sheet(isPresented:$alert){NavigationStack{AlertEditor()}}
            .sheet(isPresented:$connections){NavigationStack{ConnectionsView()}}
            .sheet(isPresented:$contractAccess){NavigationStack{ContractAccessView().id(contractAccessSession)}}
            .fullScreenCover(isPresented:$fullscreen){VStack(spacing:0){HStack{Text(instrument?.name ?? "").font(.headline);Spacer();Button("完成"){fullscreen=false}.accessibilityIdentifier("closeFullscreenChart")}.padding();ChartView(indicator:indicator,period:period,line:line,role:"fullscreen").accessibilityIdentifier("fullscreenChartWeb")}.background(Color(.systemBackground)).accessibilityElement(children:.contain).accessibilityIdentifier("fullscreenChart")}
            .task(id:"\(active)-\(instrument?.id ?? "")"){guard active,let i=instrument else{return};if browseInstrumentID==nil{model.focusTradeProduct(i)}else{model.focusProduct(i)};if let p=model.state?.chartPreferences?[i.id]{indicator=p.indicator;period=p.period;line=p.line;model.interval=p.interval}else{indicator="MA";period=20;line=false;model.interval=60};consumeFormRequest();await model.loadChart();await model.loadNews()}
            .onChange(of:model.tradeFormRequest){_,_ in consumeFormRequest()}
            .onChange(of:indicator){_,_ in saveChart()}.onChange(of:period){_,_ in saveChart()}.onChange(of:line){_,_ in saveChart()}
    }
    private func applyPickerChoice(){
        guard let choice=pickerChoice else{return};pickerChoice=nil
        guard model.context==choice.context,let i=model.state?.instruments.first(where:{choice.product.matches($0)}) else{return}
        model.requestTrade(i,side:choice.side,openForm:false,board:choice.board)
    }
    private var tradeSelector:some View{VStack(alignment:.leading,spacing:8){
        Button{choosingProduct=true}label:{HStack{VStack(alignment:.leading){Text(instrument?.name ?? "選擇交易商品").font(.headline);Text((instrument?.symbol ?? "搜尋、分類、自選或最近查看")+" · "+(instrument?.identity?.exchange ?? "")).font(.caption)};Spacer();Image(systemName:"chevron.down")}.frame(maxWidth:.infinity,minHeight:44)}.accessibilityIdentifier("tradeProductPicker")
        if let i=instrument{Text((model.context?.mode.label ?? "")+" · "+MarketText.orderDirection(i,side:model.tradeWorkspace?.side ?? .buy,reduceOnly:false)).font(.caption).accessibilityIdentifier("tradeWorkspaceSummary")}
        if model.tradeWorkspace?.editor != nil{Label("有未送出草稿；按買賣可繼續編輯",systemImage:"pencil.line").font(.caption).foregroundStyle(.orange)}
    }.padding(18).background(Color(.secondarySystemGroupedBackground))}
    private func beginTrade(_ i:Instrument,_ side:Side){
        if browseInstrumentID != nil{model.requestTrade(i,side:side,openForm:true,board:model.selectedBoard)}
        else if model.tradeWorkspace?.editor != nil && model.tradeWorkspace?.side != side{model.requestTrade(i,side:side,openForm:true,board:model.selectedBoard)}
        else{model.requestTrade(i,side:side,openForm:false,board:model.selectedBoard);openForm(side)}
    }
    private func consumeFormRequest(){guard browseInstrumentID==nil,model.tab==2,model.tradeFormRequest != nil else{return};model.tradeFormRequest=nil;openForm(model.tradeWorkspace?.side ?? .buy)}
    private func openForm(_ side:Side){
        guard let i=model.tradeInstrument,let context=model.context,model.canTrade(i) else{return}
        draft=OrderDraft(instrument:i,context:context,side:side,board:model.tradeWorkspace?.board ?? (i.usesTaiwanBoards ? .oddLot:.regular),closingPosition:model.tradeClosingPosition,workspaceSession:model.tradeSession);model.tradeClosingPosition=nil
    }
    private func productContent(_ i:Instrument)->some View{
        VStack(alignment:.leading,spacing:20){
            productHeader(i)
            if i.usesTaiwanBoards{HStack(spacing:4){ForEach(TradingBoard.allCases,id:\.self){board in
                Button{
                    #if DEBUG
                    if UITestSupport.session != nil{model.uiTestBoardRequests=Array((model.uiTestBoardRequests+[board.rawValue]).suffix(20))}
                    #endif
                    if browseInstrumentID==nil{model.requestTrade(i,side:model.tradeWorkspace?.side ?? .buy,openForm:false,board:board)}else{model.changeBoard(board)}
                }label:{Text(board.label).font(.subheadline).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                .buttonStyle(.plain).background(model.selectedBoard==board ? Color.accentColor.opacity(0.2):Color.clear,in:RoundedRectangle(cornerRadius:9))
                .accessibilityAddTraits(model.selectedBoard==board ? .isSelected:[]).accessibilityIdentifier("board-"+board.rawValue)
            }}.padding(4).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:12)).accessibilityElement(children:.contain).accessibilityLabel("台股交易盤別")}
            MarketRefreshStatus(instrument:i)
            if browseInstrumentID==nil{holdingSection(i)}
            chartSection
            simulationSection(i)
            connectionSection(i)
            bookSection
            if browseInstrumentID != nil{holdingSection(i)}
            contractSection(i)
            relatedNews(i)
            NavigationLink("近期成交與委託"){OrdersView()}
            Text("已到商品頁底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("productBottom")
        }.padding(18).padding(.bottom,12)
    }
    @ViewBuilder private func simulationSection(_ i:Instrument)->some View{
        if model.state?.simulation != nil{SimulationControls();if !i.boardIsOpen(i.usesTaiwanBoards ? model.selectedBoard:nil,at:model.now){Button("順序推進至下一交易時段"){Task{await model.nextSession()}}.buttonStyle(.bordered)}}
    }
    @ViewBuilder private func connectionSection(_ i:Instrument)->some View{
        let status=model.status(for:i,board:i.usesTaiwanBoards ? model.selectedBoard:nil)
        if status != .ready{MarketCard{
            QuoteStatusLabel(status:status)
            Text(status.nextStep).font(.subheadline).foregroundStyle(.secondary)
            if model.state?.mode == .online{HStack{Button("重試行情"){Task{await model.fetchQuotes()}};Button("行情連線"){connections=true}}}
        }}
    }
    @ViewBuilder private var bookSection:some View{
        if let i=instrument,model.canTrade(i),let q=quote,q.valid,[ExecutionGrade.E1,.E2].contains(q.grade),!q.bids.isEmpty,!q.asks.isEmpty{
            let subtitle=model.state?.mode == .offline ? "本機模擬對手盤；數量依商品單位":"來源提供的買賣盤；本機成交會消耗可用流動性"
            MarketCard{MarketSectionTitle(title:"買賣盤",subtitle:subtitle).accessibilityIdentifier("productBookTitle");HStack(alignment:.top,spacing:18){BookSide(instrument:i,title:"買盤",levels:(try? SimulationParticipants.displayLevels(q.bids,usage:model.state?.participantUsage)) ?? [],color:.green);BookSide(instrument:i,title:"賣盤",levels:(try? SimulationParticipants.displayLevels(q.asks,usage:model.state?.participantUsage)) ?? [],color:.red)}}
        }else if model.state?.mode == .online{Text("目前沒有可供撮合的可靠買賣盤。可查看既有部位、委託與歷史，也可撤銷本機委託。").font(.footnote).foregroundStyle(.secondary)}
    }
    @ViewBuilder private func holdingSection(_ i:Instrument)->some View{
        let positions=model.state?.heldPositions(i.id) ?? []
        if !positions.isEmpty{MarketCard{
            MarketSectionTitle(title:"我的持倉")
            ForEach(positions){position in
                HStack{Metric(title:(position.side?.label ?? "數量")+"（\(i.quantityUnit)）",value:MarketText.number(position.quantity));Metric(title:"平均成本",value:MarketText.number(position.average))}
                if i.asset.derivative,position.quantity != .zero,model.context != nil{
                    if browseInstrumentID != nil{
                        Button(position.quantity > .zero ? "平多（僅減倉）":"平空（僅減倉）"){beginClosing(position,instrument:i)}
                            .frame(minHeight:44).buttonStyle(.bordered).disabled(model.interactionBlocked || !model.canTrade(i)).accessibilityIdentifier("marketClosePosition-"+position.id)
                    }
                    if position.marginMode == .isolated{NavigationLink("調整逐倉保證金"){MarginEditor(initialPositionID:position.id)}}
                }
                if i.asset.derivative{ContractPositionRiskView(position:position)}
            }
            Button("查看資產與損益"){model.tab=4}
        }}
    }
    @ViewBuilder private func contractSection(_ i:Instrument)->some View{
        if i.asset.derivative{MarketCard{
            MarketSectionTitle(title:"合約風險")
            Text("開多／開空與現貨買賣不同。槓桿可能造成強平及穿倉，所有負債保留；合約規則與資金費依此商品規格。").font(.footnote).foregroundStyle(.orange)
            if let q=quote{LabeledContent("風險參考價",value:MarketText.number(q.mark));if let funding=q.fundingRate{LabeledContent("目前資金費率",value:funding.description)}}
            Button("查看契約與規則"){details=true}
        }}
    }
    private func relatedNews(_ i:Instrument)->some View{
        let category=i.asset == .perpetual ? "合約":i.asset == .crypto ? "現貨":"全部"
        let stories=MarketNewsSelection.filter(model.marketNews,instruments:model.state?.instruments ?? [],market:i.market,category:category,watchlist:model.state?.watchlist ?? [],favoritesOnly:false,now:model.now,origin:model.state?.mode == .offline ? .simulated:.real).filter{$0.instrumentIDs.isEmpty || $0.instrumentIDs.contains(i.id)}
        return VStack(alignment:.leading,spacing:16){
            MarketSectionTitle(title:"相關新聞與事件")
            ForEach(Array(stories.prefix(3))){story in NavigationLink{MarketNewsDetail(story:story)}label:{MarketNewsCard(story:story)}.buttonStyle(.plain)}
            if stories.isEmpty{Text("目前沒有已取得的相關新聞。").font(.footnote).foregroundStyle(.secondary)}
            NavigationLink("查看全部市場新聞"){MarketNewsView(initialCategory:category,domain:i.market)}
        }
    }
    private func saveChart(){guard active,let id=instrument?.id,let context=model.context else{return};let capturedIndicator=indicator,capturedPeriod=period,capturedLine=line,capturedInterval=model.interval;Task{guard model.context==context,let engine=model.engine else{return};await model.run{try await engine.saveChartPreferences(instrumentID:id,preferences:ChartPreferences(interval:capturedInterval,indicator:capturedIndicator,period:capturedPeriod,line:capturedLine),context:context)}}}
    private func productHeader(_ i:Instrument)->some View{
        let summary=model.summary(for:i)
        let change=MarketText.change(quote,summary:summary,instrument:i)
        return VStack(alignment:.leading,spacing:12){
            HStack(alignment:.top){VStack(alignment:.leading,spacing:5){Text(i.name).font(.title2.bold());Text(i.symbol+" · "+(i.identity?.exchange ?? i.asset.label)+" · "+i.currency).font(.caption).foregroundStyle(.secondary)};Spacer();Button{Task{await model.toggleWatch(i.id)}}label:{Image(systemName:model.state?.watchlist.contains(i.id)==true ? "star.fill":"star").frame(minWidth:36,minHeight:44)}.accessibilityLabel("切換自選").disabled(model.interactionBlocked).accessibilityIdentifier("toggleWatch").accessibilityValue(model.state?.watchlist.contains(i.id)==true ? "已加入":"未加入");Button{details=true}label:{Image(systemName:"info.circle").frame(minWidth:30,minHeight:44)}.accessibilityLabel("商品規格")}
            Text(MarketText.price(quote?.last,instrument:i)).font(.system(size:34,weight:.bold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            Text(change?.0 ?? "漲跌資料尚未提供").font(.subheadline.monospacedDigit()).lineLimit(1).foregroundStyle(change.map{$0.1 >= .zero ? (model.settings.taiwanColors ? Color.red:Color.green):(model.settings.taiwanColors ? Color.green:Color.red)} ?? Color.secondary)
            HStack{QuoteStatusLabel(status:model.status(for:i,board:i.usesTaiwanBoards ? model.selectedBoard:nil));Spacer();if let q=quote{Text(Date(timeIntervalSince1970:TimeInterval(q.time)).formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)}}
            // Keep the controls below this header stationary while the async
            // summary arrives. Unknown values are explicit placeholders, never0.
            HStack(alignment:.top,spacing:12){
                headerMetric((summary?.window ?? (i.market == .crypto ? "24小時":"當日"))+"量",value:summary.map{MarketText.quantity($0.volume,instrument:i)} ?? "—")
                headerMetric("最高",value:MarketText.price(summary?.high,instrument:i))
                headerMetric("最低",value:MarketText.price(summary?.low,instrument:i))
            }.accessibilityElement(children:.contain).accessibilityIdentifier("productSummaryMetrics").accessibilityValue(summary==nil ? "等待摘要":"摘要已更新")
            if model.state?.mode == .offline{Text("價格、成交與事件均為離線模擬").font(.caption).foregroundStyle(.orange)}
        }
    }
    private func headerMetric(_ title:String,value:String)->some View{
        VStack(alignment:.leading,spacing:4){
            Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var chartSection:some View{MarketCard{
        ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(intervals,id:\.1){label,seconds in Button(label){model.interval=seconds;saveChart();Task{await model.loadChart()}}.font(.caption).buttonStyle(.bordered).tint(model.interval==seconds ? .orange:.gray)}}}
        ViewThatFits(in:.horizontal){HStack{chartActions;Spacer();alertAction};VStack(alignment:.leading,spacing:12){chartActions;alertAction}}
        if model.chartLoading || model.selectedID != instrument?.id{ProgressView("讀取K線…").font(.caption)}
        if let limitation=model.chartLimitation{Label(limitation,systemImage:"info.circle").font(.caption).foregroundStyle(.orange).accessibilityIdentifier("chartSourceLimitation")}
        if let error=model.chartError{ContentUnavailableView("此範圍暫無K線",systemImage:"chart.xyaxis.line",description:Text(error)).frame(minHeight:200)}else if active,model.selectedID==instrument?.id{ChartView(indicator:indicator,period:period,line:line,interactionEnabled:draft == nil && !choosingProduct && !details && !drawing && !alert && !connections && !contractAccess && !fullscreen).accessibilityHidden(draft != nil || choosingProduct || details || drawing || alert || connections || contractAccess || fullscreen).allowsHitTesting(draft == nil && !choosingProduct && !details && !drawing && !alert && !connections && !contractAccess && !fullscreen).frame(height:330).clipShape(RoundedRectangle(cornerRadius:10)).accessibilityIdentifier("inlineChartWeb")}
        Text("圖表左右拖動／雙指縮放；上下滑動頁面。橫向圖表可調整價格軸。").font(.caption2).foregroundStyle(.secondary)
        indicatorPicker
        ViewThatFits(in:.horizontal){historyActions;VStack(alignment:.leading,spacing:12){historyNavigation;drawingActions}}
    }}
    private var alertAction:some View{Button("到價提醒"){alert=true}.font(.caption).padding(.vertical,8).accessibilityIdentifier("openPriceAlert")}
    private var historyNavigation:some View{HStack{Button("更多歷史"){Task{await model.loadEarlierChart()}}.disabled(model.chartLoading);if model.chartBefore != nil{Button("返回最新"){Task{await model.loadLatestChart()}}}}.font(.caption)}
    private var drawingActions:some View{HStack{Button("繪圖"){drawing=true};Button(model.chartCapturing ? "截圖中…":"截圖"){Task{await model.captureChart()}}.disabled(model.chartCapturing || model.chartLoading).accessibilityIdentifier("captureChart")}.font(.caption)}
    private var historyActions:some View{HStack{historyNavigation;Spacer();drawingActions}}
    private var indicatorPicker:some View{HStack{Picker("指標",selection:$indicator){ForEach(["無","MA","EMA","MACD","RSI","KD","BOLL","VWAP","ATR"],id:\.self){Text($0)}}.labelsHidden();Stepper("\(period)",value:$period,in:2...100).font(.caption).frame(maxWidth:150)}}
    private var chartActions:some View{HStack{Button{line.toggle()}label:{Label("線圖／K線",systemImage:line ? "chart.bar.xaxis":"waveform.path")};Button{fullscreen=true}label:{Label("橫向圖表",systemImage:"arrow.up.left.and.arrow.down.right")}.accessibilityIdentifier("openFullscreenChart")}.font(.caption).padding(.vertical,8)}
    private func beginClosing(_ position:Position,instrument:Instrument){
        guard draft==nil,model.pendingTrade==nil else{return}
        model.requestTrade(instrument,side:position.quantity > .zero ? .sell:.buy,openForm:true,board:model.selectedBoard,closingPosition:position)
    }
    @ViewBuilder private var positionCloseActions:some View{
        if browseInstrumentID==nil,let i=instrument,i.asset.derivative,model.context != nil{
            let positions=(model.state?.heldPositions(i.id) ?? []).filter{$0.quantity != .zero}
            if !positions.isEmpty{
                HStack(spacing:12){ForEach(positions){position in
                    Button{beginClosing(position,instrument:i)}label:{VStack(spacing:2){
                        Text(position.quantity > .zero ? "平多（僅減倉）":"平空（僅減倉）").font(.subheadline.weight(.semibold))
                        Text(MarketText.number(position.quantity.magnitude)+" "+i.quantityUnit).font(.caption)
                    }.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}
                        .buttonStyle(.bordered).disabled(model.interactionBlocked || !model.canTrade(i)).accessibilityIdentifier("closePosition-"+position.id)
                }}.padding(.horizontal,18).padding(.vertical,4)
            }
        }
    }
    private var tradeBar:some View{
        VStack(spacing:0){positionCloseActions;tradeEntryActions}
            .background(Color(.systemBackground)).accessibilityElement(children:.contain).accessibilityIdentifier("tradeActionBar")
    }
    @ViewBuilder private var tradeEntryActions:some View{
        if let i=instrument,i.asset.derivative,model.canTrade(i),model.state?.leverageEnabled != true{HStack{VStack(alignment:.leading){Text("合約功能尚未啟用").font(.subheadline);Text("既有部位仍可平倉").font(.caption).foregroundStyle(.secondary)};Spacer();Button("了解與啟用"){contractAccessSession=UUID();contractAccess=true}.buttonStyle(.borderedProminent).accessibilityIdentifier("enableContractTrading")}.padding(12).background(Color(.systemBackground)).accessibilityElement(children:.contain).accessibilityIdentifier("tradeEntryActions")}
        else if let i=instrument,i.asset != .index,model.canTrade(i),model.context != nil{HStack(spacing:12){Button(i.buyLabel){beginTrade(i,.buy)}.accessibilityIdentifier("openOrder");Button(i.sellLabel){beginTrade(i,.sell)}.accessibilityIdentifier("openSellOrder")}.font(.headline).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity).padding(.horizontal,18).padding(.vertical,10).background(Color(.systemBackground)).accessibilityElement(children:.contain).accessibilityIdentifier("tradeEntryActions")}
        else if let i=instrument{HStack{Image(systemName:"info.circle");Text(i.asset == .index ? "指數僅供參考；請選擇相關ETF或期貨。":model.interactionBlocked ? "市場補算中，暫停新委託":"目前行情或規則不符合新委託條件").font(.caption);Spacer();Button("查看委託"){model.tab=3}}.padding(12).background(.bar)}
    }
}
struct BookSide:View{
    var instrument:Instrument
    var title:String
    var levels:[Level]
    var color:Color
    var body:some View{VStack(spacing:9){HStack{Text(title);Spacer();Text("數量")}.font(.caption).foregroundStyle(.secondary);ForEach(Array(levels.prefix(5).enumerated()),id:\.offset){_,level in HStack{Text(MarketText.price(level.price,instrument:instrument)).foregroundStyle(color);Spacer();Text(MarketText.quantity(level.quantity,instrument:instrument))}.font(.system(.caption,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.5)}}.frame(maxWidth:.infinity)}
}
private enum ContractAction:String,CaseIterable{
    case openLong,openShort,closeLong,closeShort
    var label:String{switch self{case .openLong:"開多";case .openShort:"開空";case .closeLong:"平多";case .closeShort:"平空"}}
    var side:Side{self == .openLong || self == .closeShort ? .buy:.sell}
    var positionSide:PositionSide{self == .openLong || self == .closeLong ? .long:.short}
    var closes:Bool{self == .closeLong || self == .closeShort}
}
struct OrderForm:View{
    private enum EditingField:Hashable{case price,quantity,trigger,distance,profit,stop}
    let instrument:Instrument
    let accountContext:AccountContext
    var initialSide=Side.buy
    var initialBoard=TradingBoard.regular
    var initialPosition:Position?
    var workspaceSession:UUID?=nil
    var onCancelled:(@MainActor ()->Void)?=nil
    let onSubmitted:@MainActor ()->Void
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @FocusState private var editing:EditingField?
    @State private var side=Side.buy
    @State private var contractAction=ContractAction.openLong
    @State private var kind=OrderKind.limit
    @State private var price=""
    @State private var quantity="1"
    @State private var unit="股"
    @State private var trigger=""
    @State private var distance="0.05"
    @State private var trailingPercent=true
    @State private var reference=TriggerReference.last
    @State private var tif=TimeInForce.GTC
    @State private var expiry=Date().addingTimeInterval(86400)
    @State private var postOnly=false
    @State private var reduceOnly=false
    @State private var leverage=1
    @State private var margin=MarginMode.isolated
    @State private var protection="無"
    @State private var profit=""
    @State private var stop=""
    @State private var advanced=false
    @State private var cancelling=false
    @State private var confirm=false
    @State private var choosingOrderKind=false
    @State private var sending=false
    @State private var submitted=false
    @State private var submitIssue:String?
    @State private var initialized=false
    @State private var baseline:TradeEditor?
    @State private var requestID=UUID().uuidString
    @State private var ocoRequestID=UUID().uuidString
    private var hedge:Bool{instrument.asset.derivative && model.state?.positionMode == .hedge}
    private var effectiveSide:Side{hedge ? contractAction.side:side}
    private var effectiveReduceOnly:Bool{hedge ? contractAction.closes:reduceOnly}
    private var directionLabel:String{hedge ? contractAction.label:MarketText.orderDirection(instrument,side:side,reduceOnly:reduceOnly)}
    private var selectedPosition:Position?{guard let state=model.state else{return nil};return state.positions[state.positionKey(instrument:instrument,side:hedge ? contractAction.positionSide:nil)]}
    private var board:TradingBoard?{instrument.usesTaiwanBoards ? (unit == "張" ? .regular:.oddLot):nil}
    private var quote:Quote?{model.state?.quotes[instrument.quoteKey(board:board)]}
    private var isCurrent:Bool{model.context==accountContext}
    private var orderQuantity:Amount?{guard let raw=try? Amount(quantity) else{return nil};return try? raw*Amount(instrument.usesTaiwanBoards && unit == "張" ? (instrument.identity?.boardLot ?? 1000):1)}
    var body:some View{Form{
        basicSection
        contractRiskSection
        advancedSection
        summarySection
    }.disabled(sending).scrollDismissesKeyboard(.immediately).safeAreaInset(edge:.bottom){submitSection}.background(OrderNavigationDismissObserver(enabled:!sending && !confirm && !choosingOrderKind && !submitted && !cancelling,onDismiss:cancelUnsentForm)).interactiveDismissDisabled(sending).presentationDragIndicator(.visible).overlay(alignment:.bottomLeading){UITestProbe()}.modifier(UITestVisualEnvironment()).navigationTitle("模擬下單").navigationBarTitleDisplayMode(.inline).toolbar{
        ToolbarItem(placement:.principal){
            Text("模擬下單").font(.headline).frame(maxWidth:.infinity,minHeight:44)
                .accessibilityHint("向下拖曳可取消尚未送出的委託")
        }
        ToolbarItem(placement:.topBarLeading){UITestCatchupControl()}
        ToolbarItem(placement:.topBarTrailing){Button("完成"){cancelUnsentForm()}.disabled(sending || cancelling)}
    }.sheet(isPresented:$choosingOrderKind){orderKindSelection}
        .onAppear{guard !initialized else{return};initialized=true;price=initialLimitPrice;side=initialSide;contractAction=initialSide == .buy ? .openLong:.openShort;unit=instrument.usesTaiwanBoards ? (initialBoard == .regular ? "張":"股"):instrument.quantityUnit;if instrument.usesTaiwanBoards{tif = .DAY};if instrument.asset == .crypto{quantity="0.001"};if let position=initialPosition{reduceOnly=true;side=position.quantity > .zero ? .sell:.buy;contractAction=position.quantity > .zero ? .closeLong:.closeShort;quantity=position.quantity.magnitude.description;leverage=position.leverage;margin=position.marginMode};if initialPosition==nil,workspaceSession==model.tradeSession,model.tradeWorkspace?.product.matches(instrument)==true,let saved=model.tradeWorkspace?.editor{restoreEditor(saved)};baseline=editorSnapshot}
        .onDisappear{Task{await model.flushTradeWorkspace()}}
        .onChange(of:editorSnapshot){_,value in
            guard initialized,!submitted,let session=workspaceSession else{return}
            // Ignore initial presentation only. Returning an edited form to its
            // original values is still a real edit that must replace the draft.
            guard baseline != value || model.tradeWorkspace?.editor != nil else{return}
            model.updateTradeEditor(value,instrument:instrument,context:accountContext,session:session)
        }
        .onChange(of:reduceOnly){_,closing in if closing,let position=selectedPosition{side=position.quantity > .zero ? .sell:.buy;leverage=position.leverage;margin=position.marginMode}}
        .onChange(of:unit){_,_ in if board == .oddLot{kind = .limit;tif = .DAY;postOnly=false;protection="無";model.changeBoard(.oddLot)}else if instrument.usesTaiwanBoards{model.changeBoard(.regular)}}
        .alert("確認本機模擬委託",isPresented:$confirm){Button("確認送出"){Task{await send()}};Button("取消",role:.cancel){}}message:{Text(confirmationText)}
    }
    private func cancelUnsentForm(){
        guard !sending,!submitted,!confirm,!choosingOrderKind,!cancelling else{return};cancelling=true
        #if DEBUG
        if UITestSupport.session != nil{model.uiTestOrderDismissRequests+=1}
        #endif
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        if let onCancelled{onCancelled()}else{dismiss()}
    }
    private var editorSnapshot:TradeEditor{
        var e=TradeEditor();e.side=effectiveSide;e.contractAction=hedge ? contractAction.rawValue:(effectiveReduceOnly ? (side == .buy ? "closeShort":"closeLong"):(side == .buy ? "openLong":"openShort"));e.kind=kind;e.price=price;e.quantity=quantity;e.unit=unit;e.trigger=trigger;e.distance=distance;e.trailingPercent=trailingPercent;e.reference=reference;e.tif=tif;e.expiry=Int64(expiry.timeIntervalSince1970);e.postOnly=postOnly;e.reduceOnly=reduceOnly;e.leverage=leverage;e.margin=margin;e.protection=protection;e.profit=profit;e.stop=stop;e.advanced=advanced;e.requestID=requestID;e.ocoRequestID=ocoRequestID;return e
    }
    private func restoreEditor(_ e:TradeEditor){
        side=e.side;contractAction=ContractAction(rawValue:e.contractAction) ?? .openLong;kind=e.kind;price=e.price;quantity=e.quantity;unit=e.unit;trigger=e.trigger;distance=e.distance;trailingPercent=e.trailingPercent;reference=e.reference;tif=e.tif;expiry=Date(timeIntervalSince1970:TimeInterval(e.expiry));postOnly=e.postOnly;reduceOnly=e.reduceOnly;leverage=e.leverage;margin=e.margin;protection=e.protection;profit=e.profit;stop=e.stop;advanced=e.advanced;requestID=e.requestID;ocoRequestID=e.ocoRequestID
    }
    private var availableKinds:[OrderKind]{if board == .oddLot{return [.limit]};return advanced ? OrderKind.allCases:[.market,.limit]}
    private var initialLimitPrice:String{
        guard isCurrent else{return ""}
        let key=instrument.quoteKey(board:instrument.usesTaiwanBoards ? initialBoard:nil)
        guard let last=model.state?.quotes[key]?.last,let proposed=try? instrument.rules.roundedPrice(last,.plain),proposed > .zero else{return ""}
        return proposed.description
    }
    private var orderKindSelection:some View{NavigationStack{List{
        Section("選擇後只更新表單，不會送出委託"){
            ForEach(availableKinds,id:\.self){choice in
                Button{guard !sending,!submitted,isCurrent else{return};kind=choice;choosingOrderKind=false}label:{HStack{Text(choice.label);Spacer();if choice==kind{Image(systemName:"checkmark")}}.frame(minHeight:44).contentShape(Rectangle())}
                    .accessibilityLabel(choice.label).disabled(model.interactionBlocked)
            }
        }
        if board == .oddLot{Text("盤中零股僅支援限價當日單。").font(.footnote)}
        else if !advanced{Text("其他條件類型可在原表單展開「進階委託與保護」。").font(.footnote)}
    }.navigationTitle("委託類型").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("取消選擇"){choosingOrderKind=false}}}.overlay(alignment:.bottomLeading){UITestProbe()}}.modifier(UITestVisualEnvironment())}
    private var availableMoney:String{model.money(try? model.state.map{try TradingEngine.available($0,currency:instrument.currency)})}
    private var priceTickLabel:String{
        let reference:Amount?
        let basis:String
        if [.limit,.stopLimit].contains(kind),let entered=try? Amount(price),entered > .zero{
            reference=entered;basis="依限價"
        }else{
            reference=quote?.last;basis="依目前報價"
        }
        guard let reference,reference > .zero else{
            return instrument.rules.priceTicks == nil ? instrument.rules.tick.description+" "+instrument.currency:"待有效價格"
        }
        return instrument.rules.tick(at:reference).description+" "+instrument.currency+"（"+basis+"）"
    }
    private var confirmationText:String{
        let direction=directionLabel
        return "\(accountContext.mode.label)\n\(instrument.name)（\(instrument.symbol)）\n\(instrument.identity?.exchange ?? "自訂") · \(instrument.asset.label) · \(instrument.currency)\n\(direction) · \(MarketText.number(orderQuantity))\(instrument.quantityUnit)\n\(kind.label) · \(instrument.currency)\n不會向交易所傳送委託。"
    }
    private var basicSection:some View{
        Section(instrument.name+" · "+instrument.symbol){
            Text(accountContext.mode.label+" · "+(instrument.identity?.exchange ?? "自訂")+" · "+instrument.currency).font(.caption).foregroundStyle(.secondary)
            Text("最小數量／級距："+(instrument.usesTaiwanBoards && unit=="張" ? "1 張（\(instrument.identity?.boardLot ?? 1000) 股）":instrument.rules.quantityStep.description+instrument.quantityUnit)+" · 價格級距："+priceTickLabel).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("orderTradingRules")
            if instrument.rules.minimumNotional > .zero{Text("最低委託金額："+instrument.rules.minimumNotional.description+" "+instrument.currency).font(.caption).foregroundStyle(.secondary)}
            if hedge{Picker("合約操作",selection:$contractAction){ForEach(ContractAction.allCases,id:\.self){Text($0.label)}}}else{
                if instrument.asset.derivative{Picker("合約操作",selection:$reduceOnly){Text("開倉").tag(false);Text("平倉").tag(true)}.pickerStyle(.segmented)}
                if instrument.asset.derivative && reduceOnly{LabeledContent("方向",value:directionLabel).accessibilityElement(children:.ignore).accessibilityLabel("方向").accessibilityValue(directionLabel).accessibilityAddTraits(.isStaticText).accessibilityIdentifier("orderDirection");Text("僅減少既有部位，不反向開倉。").font(.caption).foregroundStyle(.secondary)}else{Picker("方向",selection:$side){Text(instrument.buyLabel).tag(Side.buy);Text(instrument.sellLabel).tag(Side.sell)}.pickerStyle(.segmented)}
            }
            Button{editing=nil;UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil);choosingOrderKind=true}label:{HStack{Text("委託類型").foregroundStyle(.primary);Spacer();Text(kind.label);Image(systemName:"chevron.up.chevron.down").font(.caption)}.frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("orderKind").accessibilityValue(kind.label)
            if [.limit,.stopLimit].contains(kind){numericInput("限價（\(instrument.currency)）",text:$price,field:.price,identifier:"orderPrice")}
            if instrument.usesTaiwanBoards{Picker("數量單位",selection:$unit){Text("股").tag("股");Text("張").tag("張")}.pickerStyle(.segmented);Text("1 張＝\(instrument.identity?.boardLot ?? 1000) 股").font(.caption).foregroundStyle(.secondary)}
            numericInput("數量（\(unit)）",text:$quantity,field:.quantity,identifier:"orderQuantity")
            HStack{ForEach([25,50,75,100],id:\.self){percent in Button("\(percent)%"){setProportion(percent)}.font(.caption).buttonStyle(.borderless)}}
            if !instrument.asset.derivative{LabeledContent("可賣數量（\(instrument.quantityUnit)）",value:MarketText.number(model.state?.positions[instrument.id]?.quantity ?? .zero))}
            if instrument.asset.derivative{LabeledContent("可平數量（\(instrument.quantityUnit)）",value:MarketText.number(selectedPosition?.quantity.magnitude ?? .zero))}
            LabeledContent(instrument.currency+"可用",value:availableMoney)
            if (try? model.state.map{try TradingEngine.available($0,currency:instrument.currency)}) == .zero{NavigationLink("設定這個幣別的虛擬資金"){CashView(initialCurrency:instrument.currency)}}
        }
    }
    @ViewBuilder private var contractRiskSection:some View{
        if instrument.asset.derivative{Section("合約風險"){
            Stepper("槓桿 \(leverage)×",value:$leverage,in:1...instrument.rules.maxLeverage).disabled(effectiveReduceOnly)
            Picker("保證金模式",selection:$margin){Text("逐倉").tag(MarginMode.isolated);Text("全倉（同幣別）").tag(MarginMode.cross)}.disabled(effectiveReduceOnly)
            Text("虛擬合約可能強平及穿倉；全倉僅共用同帳戶、同結算幣別抵押品。").font(.caption).foregroundStyle(.orange)
        }}
    }
    @ViewBuilder private var advancedSection:some View{
        if board != .oddLot{Section{DisclosureGroup("進階委託與保護",isExpanded:$advanced){
            if kind.conditional && kind != .trailing{numericInput("觸發價（\(instrument.currency)）",text:$trigger,field:.trigger,identifier:"orderTriggerPrice")}
            if kind == .trailing{numericInput(trailingPercent ? "追蹤比例（0.05＝5%）":"追蹤距離（\(instrument.currency)）",text:$distance,field:.distance,identifier:"orderTrailingDistance");Toggle("使用百分比",isOn:$trailingPercent)}
            if kind.conditional{Picker("觸發依據",selection:$reference){ForEach(TriggerReference.allCases,id:\.self){Text($0.rawValue)}}}
            Picker("有效期限",selection:$tif){ForEach(TimeInForce.allCases,id:\.self){Text($0.rawValue)}}
            if tif == .GTD{DatePicker("到期",selection:$expiry,in:Date()...)}
            Toggle("Post-only（僅掛單）",isOn:$postOnly)
            if instrument.asset.derivative && !hedge{Toggle("Reduce-only（僅減倉）",isOn:$reduceOnly)}
            Picker("條件保護",selection:$protection){Text("無").tag("無");Text("括號（成交後保護）").tag("括號");Text("OCO（兩張退出委託）").tag("OCO")}
            if protection != "無"{numericInput("停利價（\(instrument.currency)）",text:$profit,field:.profit,identifier:"orderProfitPrice");numericInput("停損價（\(instrument.currency)）",text:$stop,field:.stop,identifier:"orderStopPrice")}
            Text("條件單只在引擎有有效資料並運作時監控。未監控期間不會補造A成交。").font(.caption).foregroundStyle(.secondary)
        }}}else{Section{Text("盤中零股採當日有效限價，獨立買賣盤與交易時段；不支援市價、跨日、IOC／FOK與Post-only。").font(.caption)}}
    }
    private var summarySection:some View{
        Section("委託摘要"){
            LabeledContent("商品",value:instrument.symbol+" · "+instrument.asset.label)
            LabeledContent("數量（\(instrument.quantityUnit)）",value:MarketText.number(orderQuantity))
            if let p=preview{LabeledContent("預估金額（\(instrument.currency)）",value:MarketText.number(p.0));LabeledContent("預估費用",value:MarketText.number(p.1));LabeledContent("預估交易稅",value:MarketText.number(p.3));if instrument.asset.derivative{LabeledContent("預估初始保證金",value:MarketText.number(p.2))}}
            if instrument.asset.derivative{ProposedContractRiskView(request:riskDraft,price:(kind == .market ? quote?.last:(try? Amount(price))))}
            Text("金額為依目前價格的估計，實際依有效買賣盤、價格保護及累計費稅撮合；可能部分成交。所有交易與資金均為模擬。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var submitSection:some View{
        VStack(spacing:0){
        if let submitIssue{Text(submitIssue).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.top,8).accessibilityIdentifier("orderSubmissionIssue")}
        Button{editing=nil;UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil);confirm=true}label:{Text(sending ? "送出中…":"檢查委託").font(.headline).frame(maxWidth:.infinity,minHeight:44).contentShape(Rectangle())}.buttonStyle(.borderedProminent).controlSize(.large).disabled(sending || submitted || choosingOrderKind || model.interactionBlocked || !isCurrent || (model.state?.mode == .online && !model.canTrade(instrument,board:board))).accessibilityIdentifier("submitOrder").padding(.horizontal,16).padding(.vertical,8)
        // The iOS keyboard toolbar floats above its reported safe area. Keeping
        // both actions in this inset lets Dynamic Type reserve their full heights.
        if editing != nil{Button("收起鍵盤"){editing=nil;UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}.font(.subheadline).frame(maxWidth:.infinity,minHeight:44).buttonStyle(.borderless).accessibilityIdentifier("orderDismissKeyboard")}
        }.background(.bar).accessibilityElement(children:.contain).accessibilityIdentifier("orderActionBar")
    }
    private func numericInput(_ title:String,text:Binding<String>,field:EditingField,identifier:String)->some View{
        VStack(alignment:.leading,spacing:6){
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier(identifier+"Label")
            TextField("輸入數值",text:text).keyboardType(.decimalPad).focused($editing,equals:field).accessibilityLabel(title).accessibilityIdentifier(identifier)
        }.accessibilityElement(children:.contain)
    }
    private var riskDraft:OrderRequest?{guard let size=orderQuantity else{return nil};var request=OrderRequest(instrumentID:instrument.id,side:effectiveSide,kind:kind,quantity:size);request.positionSide=hedge ? contractAction.positionSide:nil;request.reduceOnly=effectiveReduceOnly;request.leverage=leverage;request.marginMode=margin;return request}
    private var preview:(Amount,Amount,Amount,Amount)?{
        guard let q=orderQuantity,let p=(kind == .market ? quote?.last:(try? Amount(price))),q > .zero else{return nil}
        return try?{let notional=try q*p*instrument.rules.multiplier;return(notional,try instrument.rules.fees.cumulative(notional:notional,maker:postOnly),effectiveReduceOnly ? .zero:try instrument.rules.initialMargin(notional:notional,leverage:leverage),effectiveSide == .sell ? try notional*instrument.rules.fees.sellTax:.zero)}()
    }
    private func setProportion(_ percent:Int){
        guard let s=model.state else{return}
        do{let ratio=try Amount(percent)/Amount(100),step=instrument.rules.quantityStep
            let raw:Amount
            if effectiveReduceOnly{raw=try (selectedPosition?.quantity.magnitude ?? .zero)*ratio}
            else if effectiveSide == .sell && !instrument.asset.derivative{raw=try max(.zero,s.positions[instrument.id]?.quantity ?? .zero)*ratio}
            else if let p=quote?.last,p > .zero{raw=try TradingEngine.available(s,currency:instrument.currency)*ratio/Amount("1.06")/p/instrument.rules.multiplier*Amount(instrument.asset.derivative ? leverage:1)}else{return}
            let units=try (raw/step).rounded(0,.down),size=try units*step
            quantity=try (size/Amount(instrument.usesTaiwanBoards && unit == "張" ? (instrument.identity?.boardLot ?? 1000):1)).description
        }catch{model.error=error.localizedDescription}
    }
    private func send()async{
        guard !sending,!submitted,!model.interactionBlocked,isCurrent else{return};sending=true;submitIssue=nil;defer{sending=false}
        do{guard let size=orderQuantity else{throw TradeError.invalid("請填入正確數量")}
            var r=OrderRequest(instrumentID:instrument.id,side:effectiveSide,kind:kind,quantity:size,price:[.limit,.stopLimit].contains(kind) ? try Amount(price):nil,trigger:kind.conditional && kind != .trailing ? try Amount(trigger):nil)
            r.board=board;r.positionSide=hedge ? contractAction.positionSide:nil
            r.requestID=requestID;r.timeInForce=tif;r.expiresAt=tif == .GTD ? Int64(expiry.timeIntervalSince1970):nil;r.postOnly=postOnly;r.reduceOnly=effectiveReduceOnly;r.leverage=leverage;r.marginMode=margin;r.triggerReference=reference
            if kind == .trailing{r.trailingDistance=try Amount(distance);r.trailingPercent=trailingPercent}
            if protection == "括號"{r.bracketProfit=try Amount(profit);r.bracketStop=try Amount(stop)}
            let outcome:OrderSubmissionOutcome
            if protection == "OCO"{r.kind = .takeProfit;r.trigger=try Amount(profit);r.price=nil;r.reduceOnly=true;var second=OrderRequest(instrumentID:instrument.id,side:effectiveSide,kind:.stopMarket,quantity:size,trigger:try Amount(stop));second.positionSide=r.positionSide;second.requestID=ocoRequestID;second.reduceOnly=true;second.leverage=leverage;second.marginMode=margin;outcome=await model.submit(r,oco:second,expectedContext:accountContext)}
            else{outcome=await model.submit(r,expectedContext:accountContext)}
            switch outcome{case .accepted:submitted=true;onSubmitted();case .rejected(let message):submitIssue=message}
        }catch{submitIssue=error.localizedDescription}
    }
}

struct InstrumentDetails:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var confirmUpgrade=false
    @State private var upgrading=false
    var body:some View{Form{
        if let instrument=model.selected{
            Section("商品身份"){
                LabeledContent("商品ID",value:instrument.id);LabeledContent("類別",value:instrument.asset.label)
                LabeledContent("交易所",value:instrument.identity?.exchange ?? "自訂商品")
                LabeledContent("報價幣別",value:instrument.currency);LabeledContent("交易時區",value:instrument.rules.timeZone)
                LabeledContent("合約乘數",value:instrument.rules.multiplier.description)
                LabeledContent("交易單位",value:instrument.quantityUnit).accessibilityElement(children:.ignore).accessibilityLabel("交易單位").accessibilityValue(instrument.quantityUnit).accessibilityAddTraits(.isStaticText).accessibilityIdentifier("specQuantityUnit")
                if instrument.usesTaiwanBoards{
                    LabeledContent("整股單位",value:"1 張 = \(instrument.identity?.boardLot ?? 1000) 股").accessibilityElement(children:.ignore).accessibilityLabel("整股單位").accessibilityValue("1 張 = \(instrument.identity?.boardLot ?? 1000) 股").accessibilityAddTraits(.isStaticText).accessibilityIdentifier("specBoardLot")
                    LabeledContent("目前盤別",value:model.selectedBoard.label)
                    Text("整股以張輸入，盤中零股以股輸入；最小數量與價格級距依所選盤別核對。").font(.footnote)
                }
                LabeledContent("最小數量／數量級距",value:instrument.usesTaiwanBoards && model.selectedBoard == .regular ? "1 張（\(instrument.identity?.boardLot ?? 1000) 股）":instrument.rules.quantityStep.description+" "+instrument.quantityUnit).accessibilityElement(children:.ignore).accessibilityLabel("最小數量／數量級距").accessibilityValue(instrument.usesTaiwanBoards && model.selectedBoard == .regular ? "1 張（\(instrument.identity?.boardLot ?? 1000) 股）":instrument.rules.quantityStep.description+" "+instrument.quantityUnit).accessibilityAddTraits(.isStaticText).accessibilityIdentifier("specQuantityStep")
                LabeledContent("價格級距",value:instrument.rules.tick(at:model.quote?.last ?? .zero).description+" "+instrument.currency).accessibilityIdentifier("specPriceTick")
                LabeledContent("價格小數位數",value:String(MarketText.pricePrecision(instrument,at:model.quote?.last))).accessibilityElement(children:.ignore).accessibilityLabel("價格小數位數").accessibilityValue(String(MarketText.pricePrecision(instrument,at:model.quote?.last))).accessibilityAddTraits(.isStaticText).accessibilityIdentifier("specPricePrecision")
                if instrument.rules.priceTicks != nil{Text("價格級距依價格區間變動；此處按目前價格顯示，送單時再次驗證。").font(.footnote)}
                if instrument.rules.minimumNotional > .zero{LabeledContent("最低委託金額",value:instrument.rules.minimumNotional.description+" "+instrument.currency)}
            }
            Section("交易規則"){
                LabeledContent("規則版本",value:instrument.rules.version);Text(instrument.rules.source)
                if let years=instrument.rules.calendarYears{Text("已核對假日日曆："+years.map(String.init).joined(separator:"、")+"；其他年度與臨時休市不冒充已驗證。").font(.caption)}
                Text(instrument.rules.verifiedAt == nil ? "規則尚未完成所有官方現行制度核驗，請查看模擬規則與限制。":"規則已記錄核驗時間").foregroundStyle(.orange)
                if (instrument.identity?.catalogVersion ?? InstrumentCatalog.version)<InstrumentCatalog.version && instrument.identity?.legacy != true{
                    Text("此商品保留舊版交易單位與委託規格，尚未套用新的股／張分盤。原有部位與委託不會因更新而改寫。").font(.footnote)
                    Button(upgrading ? "升級中…":"核對並升級此商品規則"){confirmUpgrade=true}.disabled(upgrading || model.interactionBlocked)
                }
                NavigationLink("自訂規則／費率／交割"){RuleEditor()}
            }
            if let quote=model.quote{Section("行情限制"){Text(quote.coverage);LabeledContent("標記價",value:quote.mark?.description ?? "未提供")}}
        }
    }.navigationTitle("商品規格").toolbar{Button("完成"){dismiss()}}
        .confirmationDialog("升級此商品的內建交易規則？",isPresented:$confirmUpgrade,titleVisibility:.visible){
            Button("核對身份並升級"){
                guard !upgrading,let id=model.selected?.id,let context=model.context,let engine=model.engine else{return};upgrading=true
                Task{defer{upgrading=false};if await model.run({try await engine.adoptCatalogRules(instrumentID:id,context:context)}){model.selectedBoard = .oddLot;await model.fetchQuotes()}}
            };Button("取消",role:.cancel){}
        }message:{Text("必須沒有持倉與未結委託才可升級；不會替你清倉、取消委託或清除歷史。")}
    }
}
