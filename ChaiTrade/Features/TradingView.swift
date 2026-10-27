import SwiftUI
import ChaiTradeCore

private struct OrderDraft:Identifiable{
    let id=UUID()
    let instrument:Instrument
    let context:AccountContext
    let side:Side
    let board:TradingBoard
}
struct TradingView:View{
    @EnvironmentObject var model:AppModel
    @State private var draft:OrderDraft?
    @State private var showOrdersAfterDismiss=false
    @State private var fullscreen=false
    @State private var details=false
    @State private var drawing=false
    @State private var alert=false
    @State private var connections=false
    @State private var indicator="MA"
    @State private var period=20
    @State private var line=false
    private let intervals:[(String,Int64)]=[("1分",60),("5分",300),("15分",900),("30分",1800),("1時",3600),("4時",14400),("日",86400),("週",604800),("月",2592000)]
    var body:some View{
        ScrollView{
            if let i=model.selected{
                productContent(i)
            }else{ContentUnavailableView("先選擇商品",systemImage:"chart.xyaxis.line",description:Text("前往行情頁搜尋代碼或名稱"));Button("探索行情"){model.tab=1}}
        }.background(Color(.systemGroupedBackground)).navigationTitle("商品詳情").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge:.bottom){tradeBar}
            .sheet(item:$draft,onDismiss:{if showOrdersAfterDismiss{showOrdersAfterDismiss=false;model.tab=3}}){intent in NavigationStack{OrderForm(instrument:intent.instrument,accountContext:intent.context,initialSide:intent.side,initialBoard:intent.board,onSubmitted:{showOrdersAfterDismiss=true;draft=nil})}}
            .sheet(isPresented:$details){NavigationStack{InstrumentDetails()}}
            .sheet(isPresented:$drawing){NavigationStack{DrawingEditor()}}
            .sheet(isPresented:$alert){NavigationStack{AlertEditor()}}
            .sheet(isPresented:$connections){NavigationStack{ConnectionsView()}}
            .fullScreenCover(isPresented:$fullscreen){VStack(spacing:0){HStack{Text(model.selected?.name ?? "").font(.headline);Spacer();Button("完成"){fullscreen=false}}.padding();ChartView(indicator:indicator,period:period,line:line)}.background(Color(.systemBackground)).accessibilityIdentifier("fullscreenChart")}
            .task(id:model.selectedID){if let p=model.state?.chartPreferences?[model.selectedID]{indicator=p.indicator;period=p.period;line=p.line;model.interval=p.interval};await model.loadChart();await model.loadNews()}
            .onChange(of:indicator){_,_ in saveChart()}.onChange(of:period){_,_ in saveChart()}.onChange(of:line){_,_ in saveChart()}
    }
    private func productContent(_ i:Instrument)->some View{
        VStack(alignment:.leading,spacing:20){
            productHeader(i)
            if i.usesTaiwanBoards{Picker("台股交易盤別",selection:Binding(get:{model.selectedBoard},set:{model.changeBoard($0)})){ForEach(TradingBoard.allCases,id:\.self){Text($0.label)}}.pickerStyle(.segmented)}
            chartSection
            simulationSection(i)
            connectionSection(i)
            bookSection
            holdingSection(i)
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
        if let q=model.quote,q.valid,[ExecutionGrade.E1,.E2].contains(q.grade),!q.bids.isEmpty,!q.asks.isEmpty{
            let subtitle=model.state?.mode == .offline ? "本機模擬對手盤；數量依商品單位":"來源提供的買賣盤；本機成交會消耗可用流動性"
            MarketCard{MarketSectionTitle(title:"買賣盤",subtitle:subtitle);HStack(alignment:.top,spacing:18){BookSide(title:"買盤",levels:q.bids,color:.green);BookSide(title:"賣盤",levels:q.asks,color:.red)}}
        }else if model.state?.mode == .online{Text("目前沒有可供撮合的可靠買賣盤。可查看既有部位、委託與歷史，也可撤銷本機委託。").font(.footnote).foregroundStyle(.secondary)}
    }
    @ViewBuilder private func holdingSection(_ i:Instrument)->some View{
        if let position=model.state?.positions[i.id],position.quantity != .zero{MarketCard{
            MarketSectionTitle(title:"我的持倉")
            HStack{Metric(title:"數量（\(i.quantityUnit)）",value:MarketText.number(position.quantity));Metric(title:"平均成本",value:MarketText.number(position.average))}
            if i.asset.derivative{HStack{Metric(title:"保證金",value:MarketText.number(position.margin));Metric(title:"槓桿",value:"\(position.leverage)×")}}
            Button("查看資產與損益"){model.tab=4}
        }}
    }
    @ViewBuilder private func contractSection(_ i:Instrument)->some View{
        if i.asset.derivative{MarketCard{
            MarketSectionTitle(title:"合約風險")
            Text("開多／開空與現貨買賣不同。槓桿可能造成強平及穿倉，所有負債保留；合約規則與資金費依此商品規格。").font(.footnote).foregroundStyle(.orange)
            if let q=model.quote{LabeledContent("風險參考價",value:MarketText.number(q.mark));if let funding=q.fundingRate{LabeledContent("目前資金費率",value:funding.description)}}
            Button("查看契約與規則"){details=true}
        }}
    }
    private func relatedNews(_ i:Instrument)->some View{
        let stories=model.filteredNews.filter{$0.instrumentIDs.isEmpty || $0.instrumentIDs.contains(i.id)}
        return VStack(alignment:.leading,spacing:16){
            MarketSectionTitle(title:"相關新聞與事件")
            ForEach(Array(stories.prefix(3))){story in NavigationLink{MarketNewsDetail(story:story)}label:{MarketNewsCard(story:story)}.buttonStyle(.plain)}
            if stories.isEmpty{Text("目前沒有已取得的相關新聞。").font(.footnote).foregroundStyle(.secondary)}
            NavigationLink("查看全部市場新聞"){MarketNewsView()}
        }
    }
    private func saveChart(){Task{await model.saveChartPreferences(indicator:indicator,period:period,line:line)}}
    private func productHeader(_ i:Instrument)->some View{
        VStack(alignment:.leading,spacing:12){
            HStack(alignment:.top){VStack(alignment:.leading,spacing:5){Text(i.name).font(.title2.bold());Text(i.symbol+" · "+(i.identity?.exchange ?? i.asset.label)+" · "+i.currency).font(.caption).foregroundStyle(.secondary)};Spacer();Button{Task{await model.toggleWatch(i.id)}}label:{Image(systemName:model.state?.watchlist.contains(i.id)==true ? "star.fill":"star").frame(minWidth:36,minHeight:44)}.accessibilityLabel("切換自選").disabled(model.interactionBlocked).accessibilityIdentifier("toggleWatch").accessibilityValue(model.state?.watchlist.contains(i.id)==true ? "已加入":"未加入");Button{details=true}label:{Image(systemName:"info.circle").frame(minWidth:30,minHeight:44)}.accessibilityLabel("商品規格")}
            Text(MarketText.number(model.quote?.last)).font(.system(size:34,weight:.bold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            if let change=MarketText.change(model.quote,summary:model.summary(for:i)){Text(change.0).font(.subheadline.monospacedDigit()).foregroundStyle(change.1 >= .zero ? (model.settings.taiwanColors ? Color.red:Color.green):(model.settings.taiwanColors ? Color.green:Color.red))}
            HStack{QuoteStatusLabel(status:model.status(for:i,board:i.usesTaiwanBoards ? model.selectedBoard:nil));Spacer();if let q=model.quote{Text(Date(timeIntervalSince1970:TimeInterval(q.time)).formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)}}
            if let summary=model.summary(for:i){HStack{Metric(title:summary.window+"量",value:MarketText.number(summary.volume));if let high=summary.high{Metric(title:"最高",value:MarketText.number(high))};if let low=summary.low{Metric(title:"最低",value:MarketText.number(low))}}}
            if model.state?.mode == .offline{Text("價格、成交與事件均為離線模擬").font(.caption).foregroundStyle(.orange)}
        }
    }
    private var chartSection:some View{MarketCard{
        ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(intervals,id:\.1){label,seconds in Button(label){model.interval=seconds;saveChart();Task{await model.loadChart()}}.font(.caption).buttonStyle(.bordered).tint(model.interval==seconds ? .orange:.gray)}}}
        if model.chartLoading{ProgressView("讀取K線…").font(.caption)}
        if let error=model.chartError{ContentUnavailableView("此範圍暫無K線",systemImage:"chart.xyaxis.line",description:Text(error)).frame(minHeight:200)}else{ChartView(indicator:indicator,period:period,line:line).frame(height:330).clipShape(RoundedRectangle(cornerRadius:10))}
        ViewThatFits(in:.horizontal){chartTools;VStack(alignment:.leading,spacing:10){indicatorPicker;chartActions}}
        HStack{Button("更多歷史"){Task{await model.loadEarlierChart()}}.disabled(model.chartLoading);if model.chartBefore != nil{Button("返回最新"){Task{await model.loadLatestChart()}}};Spacer();Button("繪圖"){drawing=true};Button("到價提醒"){alert=true};Button("截圖"){Task{await model.captureChart()}}}.font(.caption)
    }}
    private var indicatorPicker:some View{HStack{Picker("指標",selection:$indicator){ForEach(["無","MA","EMA","MACD","RSI","KD","BOLL","VWAP","ATR"],id:\.self){Text($0)}}.labelsHidden();Stepper("\(period)",value:$period,in:2...100).font(.caption).frame(maxWidth:150)}}
    private var chartActions:some View{HStack{Button{line.toggle()}label:{Label("線圖／K線",systemImage:line ? "chart.bar.xaxis":"waveform.path")};Button{fullscreen=true}label:{Label("橫向圖表",systemImage:"arrow.up.left.and.arrow.down.right")}.accessibilityIdentifier("openFullscreenChart")}.font(.caption)}
    private var chartTools:some View{HStack{indicatorPicker;chartActions}}
    @ViewBuilder private var tradeBar:some View{
        if let i=model.selected,i.asset != .index,model.canTrade(i),let context=model.context{HStack(spacing:12){Button(i.buyLabel){draft=OrderDraft(instrument:i,context:context,side:.buy,board:model.selectedBoard)}.accessibilityIdentifier("openOrder");Button(i.sellLabel){draft=OrderDraft(instrument:i,context:context,side:.sell,board:model.selectedBoard)}.accessibilityIdentifier("openSellOrder")}.font(.headline).buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth:.infinity).padding(.horizontal,18).padding(.vertical,10).background(.bar)}
        else if let i=model.selected{HStack{Image(systemName:"info.circle");Text(i.asset == .index ? "指數僅供參考；請選擇相關ETF或期貨。":model.interactionBlocked ? "市場補算中，暫停新委託":"目前行情或規則不符合新委託條件").font(.caption);Spacer();Button("查看委託"){model.tab=3}}.padding(12).background(.bar)}
    }
}
struct BookSide:View{
    var title:String
    var levels:[Level]
    var color:Color
    var body:some View{VStack(spacing:9){HStack{Text(title);Spacer();Text("數量")}.font(.caption).foregroundStyle(.secondary);ForEach(Array(levels.prefix(5).enumerated()),id:\.offset){_,level in HStack{Text(MarketText.number(level.price)).foregroundStyle(color);Spacer();Text(MarketText.number(level.quantity))}.font(.system(.caption,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.5)}}.frame(maxWidth:.infinity)}
}
struct OrderForm:View{
    let instrument:Instrument
    let accountContext:AccountContext
    var initialSide=Side.buy
    var initialBoard=TradingBoard.regular
    let onSubmitted:@MainActor ()->Void
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var side=Side.buy
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
    @State private var confirm=false
    @State private var sending=false
    @State private var submitted=false
    @State private var initialized=false
    @State private var requestID=UUID().uuidString
    @State private var ocoRequestID=UUID().uuidString
    private var board:TradingBoard?{instrument.usesTaiwanBoards ? (unit == "張" ? .regular:.oddLot):nil}
    private var quote:Quote?{model.state?.quotes[instrument.quoteKey(board:board)]}
    private var isCurrent:Bool{model.context==accountContext}
    private var orderQuantity:Amount?{guard let raw=try? Amount(quantity) else{return nil};return try? raw*Amount(unit == "張" ? (instrument.identity?.boardLot ?? 1000):1)}
    var body:some View{Form{
        basicSection
        contractRiskSection
        advancedSection
        summarySection
        submitSection
    }.disabled(sending).scrollDismissesKeyboard(.interactively).interactiveDismissDisabled(sending).overlay(alignment:.bottomLeading){UITestProbe()}.navigationTitle("模擬下單").toolbar{
        ToolbarItem(placement:.topBarLeading){UITestCatchupControl()}
        ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}.disabled(sending)}
    }.onAppear{guard !initialized else{return};initialized=true;price=quote?.last.description ?? "";side=initialSide;unit=instrument.usesTaiwanBoards ? (initialBoard == .regular ? "張":"股"):instrument.quantityUnit;if instrument.usesTaiwanBoards{tif = .DAY};if instrument.asset == .crypto{quantity="0.001"}}
        .onChange(of:unit){_,_ in if board == .oddLot{kind = .limit;tif = .DAY;postOnly=false;protection="無";model.changeBoard(.oddLot)}else if instrument.usesTaiwanBoards{model.changeBoard(.regular)}}
        .alert("確認本機模擬委託",isPresented:$confirm){Button("確認送出"){Task{await send()}};Button("取消",role:.cancel){}}message:{Text(confirmationText)}
    }
    private var availableKinds:[OrderKind]{if board == .oddLot{return [.limit]};return advanced ? OrderKind.allCases:[.market,.limit]}
    private var availableMoney:String{model.money(try? model.state.map{try TradingEngine.available($0,currency:instrument.currency)})}
    private var confirmationText:String{
        let direction=side == .buy ? instrument.buyLabel:instrument.sellLabel
        return "\(instrument.name)（\(instrument.symbol)）\n\(direction) · \(MarketText.number(orderQuantity))\(instrument.quantityUnit)\n\(kind.label) · \(instrument.currency)\n不會向交易所傳送委託。"
    }
    private var basicSection:some View{
        Section(instrument.name+" · "+instrument.symbol){
            Text("本機模擬委託").font(.caption).foregroundStyle(.secondary)
            Picker("方向",selection:$side){Text(instrument.buyLabel).tag(Side.buy);Text(instrument.sellLabel).tag(Side.sell)}.pickerStyle(.segmented)
            Picker("委託類型",selection:$kind){ForEach(availableKinds,id:\.self){Text($0.label)}}.accessibilityIdentifier("orderKind")
            if [.limit,.stopLimit].contains(kind){TextField("限價（\(instrument.currency)）",text:$price).keyboardType(.decimalPad)}
            if instrument.usesTaiwanBoards{Picker("數量單位",selection:$unit){Text("股").tag("股");Text("張（1,000股）").tag("張")}.pickerStyle(.segmented)}
            TextField("數量（\(unit)）",text:$quantity).keyboardType(.decimalPad).accessibilityIdentifier("orderQuantity")
            HStack{ForEach([25,50,75,100],id:\.self){percent in Button("\(percent)%"){setProportion(percent)}.font(.caption).buttonStyle(.borderless)}}
            if !instrument.asset.derivative{LabeledContent("可賣數量（\(instrument.quantityUnit)）",value:MarketText.number(model.state?.positions[instrument.id]?.quantity ?? .zero))}
            LabeledContent(instrument.currency+"可用",value:availableMoney)
        }
    }
    @ViewBuilder private var contractRiskSection:some View{
        if instrument.asset.derivative{Section("合約風險"){
            Stepper("槓桿 \(leverage)×",value:$leverage,in:1...instrument.rules.maxLeverage)
            Picker("保證金模式",selection:$margin){Text("逐倉").tag(MarginMode.isolated);Text("全倉（同幣別）").tag(MarginMode.cross)}
            Text("虛擬合約可能強平及穿倉；全倉僅共用同帳戶、同結算幣別抵押品。").font(.caption).foregroundStyle(.orange)
        }}
    }
    @ViewBuilder private var advancedSection:some View{
        if board != .oddLot{Section{DisclosureGroup("進階委託與保護",isExpanded:$advanced){
            if kind.conditional && kind != .trailing{TextField("觸發價",text:$trigger).keyboardType(.decimalPad)}
            if kind == .trailing{TextField("距離／比例（0.05＝5%）",text:$distance).keyboardType(.decimalPad);Toggle("使用百分比",isOn:$trailingPercent)}
            if kind.conditional{Picker("觸發依據",selection:$reference){ForEach(TriggerReference.allCases,id:\.self){Text($0.rawValue)}}}
            Picker("有效期限",selection:$tif){ForEach(TimeInForce.allCases,id:\.self){Text($0.rawValue)}}
            if tif == .GTD{DatePicker("到期",selection:$expiry,in:Date()...)}
            Toggle("Post-only（僅掛單）",isOn:$postOnly)
            if instrument.asset.derivative{Toggle("Reduce-only（僅減倉）",isOn:$reduceOnly)}
            Picker("條件保護",selection:$protection){Text("無").tag("無");Text("括號（成交後保護）").tag("括號");Text("OCO（兩張退出委託）").tag("OCO")}
            if protection != "無"{TextField("停利價",text:$profit).keyboardType(.decimalPad);TextField("停損價",text:$stop).keyboardType(.decimalPad)}
            Text("條件單只在引擎有有效資料並運作時監控。未監控期間不會補造A成交。").font(.caption).foregroundStyle(.secondary)
        }}}else{Section{Text("盤中零股採當日有效限價，獨立買賣盤與交易時段；不支援市價、跨日、IOC／FOK與Post-only。").font(.caption)}}
    }
    private var summarySection:some View{
        Section("委託摘要"){
            LabeledContent("商品",value:instrument.symbol+" · "+instrument.asset.label)
            LabeledContent("數量（\(instrument.quantityUnit)）",value:MarketText.number(orderQuantity))
            if let p=preview{LabeledContent("預估金額（\(instrument.currency)）",value:MarketText.number(p.0));LabeledContent("預估費用",value:MarketText.number(p.1));LabeledContent("預估交易稅",value:MarketText.number(p.3));if instrument.asset.derivative{LabeledContent("預估初始保證金",value:MarketText.number(p.2))}}
            Text("金額為依目前價格的估計，實際依有效買賣盤、價格保護及累計費稅撮合；可能部分成交。所有交易與資金均為模擬。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var submitSection:some View{
        Section{Button(sending ? "送出中…":"檢查並送出模擬委託"){confirm=true}.font(.headline).disabled(sending || submitted || model.interactionBlocked || !isCurrent || (model.state?.mode == .online && !model.canTrade(instrument,board:board))).accessibilityIdentifier("submitOrder")}    }
    private var preview:(Amount,Amount,Amount,Amount)?{
        guard let q=orderQuantity,let p=(kind == .market ? quote?.last:(try? Amount(price))),q > .zero else{return nil}
        return try?{let notional=try q*p*instrument.rules.multiplier;return(notional,try instrument.rules.fees.cumulative(notional:notional,maker:postOnly),try notional/Amount(leverage),side == .sell ? try notional*instrument.rules.fees.sellTax:.zero)}()
    }
    private func setProportion(_ percent:Int){
        guard let s=model.state else{return}
        do{let ratio=try Amount(percent)/Amount(100),step=instrument.rules.quantityStep
            let raw:Amount
            if side == .sell && !instrument.asset.derivative{raw=try max(.zero,s.positions[instrument.id]?.quantity ?? .zero)*ratio}
            else if let p=quote?.last,p > .zero{raw=try TradingEngine.available(s,currency:instrument.currency)*ratio/Amount("1.06")/p/instrument.rules.multiplier*Amount(instrument.asset.derivative ? leverage:1)}else{return}
            let units=try (raw/step).rounded(0,.down),size=try units*step
            quantity=try (size/Amount(unit == "張" ? (instrument.identity?.boardLot ?? 1000):1)).description
        }catch{model.error=error.localizedDescription}
    }
    private func send()async{
        guard !sending,!submitted,!model.interactionBlocked,isCurrent else{return};sending=true;defer{sending=false}
        do{guard let size=orderQuantity else{throw TradeError.invalid("請填入正確數量")}
            var r=OrderRequest(instrumentID:instrument.id,side:side,kind:kind,quantity:size,price:[.limit,.stopLimit].contains(kind) ? try Amount(price):nil,trigger:kind.conditional && kind != .trailing ? try Amount(trigger):nil)
            r.board=board
            r.requestID=requestID;r.timeInForce=tif;r.expiresAt=tif == .GTD ? Int64(expiry.timeIntervalSince1970):nil;r.postOnly=postOnly;r.reduceOnly=reduceOnly;r.leverage=leverage;r.marginMode=margin;r.triggerReference=reference
            if kind == .trailing{r.trailingDistance=try Amount(distance);r.trailingPercent=trailingPercent}
            if protection == "括號"{r.bracketProfit=try Amount(profit);r.bracketStop=try Amount(stop)}
            let accepted:Bool
            if protection == "OCO"{r.kind = .takeProfit;r.trigger=try Amount(profit);r.price=nil;r.reduceOnly=true;var second=OrderRequest(instrumentID:instrument.id,side:side,kind:.stopMarket,quantity:size,trigger:try Amount(stop));second.requestID=ocoRequestID;second.reduceOnly=true;second.leverage=leverage;second.marginMode=margin;accepted=await model.submit(r,oco:second,expectedContext:accountContext)}
            else{accepted=await model.submit(r,expectedContext:accountContext)}
            if accepted{submitted=true;onSubmitted()}
        }catch{model.error=error.localizedDescription}
    }
}

struct InstrumentDetails: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View { Form{if let i=model.selected{LabeledContent("商品 ID",value:i.id);LabeledContent("類別",value:i.asset.label);LabeledContent("報價幣別",value:i.currency);LabeledContent("交易時區",value:i.rules.timeZone);LabeledContent("合約乘數",value:i.rules.multiplier.description);LabeledContent("規則版本",value:i.rules.version);Text(i.rules.source);Text(i.rules.verifiedAt == nil ? "規則尚未完成官方現行制度核驗，不宣稱符合所有交易所制度。":"規則已記錄核驗時間").foregroundStyle(.orange);NavigationLink("自訂規則／費率／交割"){RuleEditor()};if let q=model.quote{Text(q.coverage);LabeledContent("標記價",value:q.mark?.description ?? "未提供")}}}.navigationTitle("商品規格").toolbar{Button("完成"){dismiss()}} }
}
