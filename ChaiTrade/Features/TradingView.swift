import SwiftUI
import ChaiTradeCore

struct TradingView: View {
    @EnvironmentObject var model: AppModel
    @State private var order=false
    @State private var fullscreen=false
    @State private var details=false
    @State private var drawing=false
    @State private var alert=false
    @State private var indicator="MA"
    @State private var period=20
    @State private var line=false
    private let intervals: [(String,Int64)] = [("1分",60),("5分",300),("15分",900),("30分",1800),("1時",3600),("4時",14400),("日",86400),("週",604800),("月",2592000)]
    var body: some View {
        ScrollView {
            if let i=model.selected {
                VStack(alignment:.leading,spacing:16) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:5){Text(i.name).font(.title2.bold());Text("\(i.symbol) / \(i.currency)").font(.caption.monospaced()).foregroundStyle(.secondary)}
                        Spacer()
                        Button{Task{await model.toggleWatch(i.id)}}label:{Image(systemName:model.state?.watchlist.contains(i.id) == true ? "star.fill":"star")}.accessibilityLabel("切換自選").disabled(model.interactionBlocked).accessibilityIdentifier("toggleWatch").accessibilityValue(model.state?.watchlist.contains(i.id)==true ? "已加入":"未加入")
                        Button{details=true}label:{Image(systemName:"info.circle")}.accessibilityLabel("商品規格")
                    }
                    HStack(alignment:.firstTextBaseline){Text(model.quote?.last.description ?? "未提供").font(.system(size:34,weight:.semibold,design:.rounded)).monospacedDigit();Spacer();Text(model.quote?.grade.rawValue ?? "E0").font(.caption.monospaced()).padding(7).background(.quaternary,in:Capsule())}
                    if let q=model.quote {
                        Text("\(q.source) · \(q.quality.rawValue)\n\(Date(timeIntervalSince1970:TimeInterval(q.time)).formatted()) · \(q.coverage)").font(.caption2).foregroundStyle(.secondary)
                    } else { Text("尚未取得行情。A 不使用合成資料替代，請配置來源後更新。").font(.caption).foregroundStyle(.orange) }
                    ScrollView(.horizontal,showsIndicators:false){HStack{ForEach(intervals,id:\.1){label,seconds in Button(label){model.interval=seconds;Task{await model.saveChartPreferences(indicator:indicator,period:period,line:line);await model.loadChart()}}.font(.caption).buttonStyle(.bordered).tint(model.interval == seconds ? .orange:.gray)}}}
                    if model.chartLoading{ProgressView("讀取歷史行情…").font(.caption)}
                    if let error=model.chartError { Text(error).font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,minHeight:200) }
                    else { ChartView(indicator:indicator,period:period,line:line).frame(height:330).clipShape(RoundedRectangle(cornerRadius:12)) }
                    HStack {
                        Picker("指標",selection:$indicator){ForEach(["無","MA","EMA","MACD","RSI","KD","BOLL","VWAP","ATR"],id:\.self){Text($0)}}.labelsHidden()
                        Stepper("\(period)",value:$period,in:2...100).font(.caption).frame(maxWidth:150)
                        Button{line.toggle()}label:{Image(systemName:line ? "chart.bar.xaxis":"waveform.path")}.accessibilityLabel("切換線圖與 K 線")
                        Button{fullscreen=true}label:{Image(systemName:"arrow.up.left.and.arrow.down.right")}.accessibilityLabel("全螢幕圖表")
                    }
                    HStack{Button("更多歷史"){Task{await model.loadEarlierChart()}}.disabled(model.chartLoading);if model.chartBefore != nil{Button("返回最新"){Task{await model.loadLatestChart()}}};Spacer();Button("繪圖"){drawing=true};Button("到價提醒"){alert=true};Button("截圖"){Task{await model.captureChart()}}}.font(.caption)
                    if model.state?.simulation != nil { SimulationControls();if let s=model.state?.simulation,!i.rules.isOpen(at:s.time){Button("順序推進至下一交易時段"){Task{await model.nextSession()}}.font(.caption)}}
                    HStack(alignment:.top,spacing:18) {
                        BookSide(title:"買盤",levels:model.quote?.bids ?? [],color:.green)
                        BookSide(title:"賣盤",levels:model.quote?.asks ?? [],color:.red)
                    }
                    if model.quote?.grade == .E3 { Text("E3 只有參考價，未提供真實五檔。估算撮合須至設定明確啟用，成交紀錄會保留估算標示。").font(.caption).foregroundStyle(.orange) }
                    if let position=model.state?.positions[i.id],position.quantity != .zero {
                        HStack{Metric(title:"持倉",value:position.quantity.description);Metric(title:"平均成本",value:position.average.description);Metric(title:"鎖定保證金",value:position.margin.description)}
                    }
                    if i.asset == .index { Text("參考指數不可直接買入。可至行情頁尋找相關 ETF 或期貨。").font(.footnote).foregroundStyle(.secondary) }
                    else { Button("開啟模擬下單面板"){order=true}.font(.headline).frame(maxWidth:.infinity).padding().background(.orange,in:RoundedRectangle(cornerRadius:14)).foregroundStyle(.black).accessibilityIdentifier("openOrder").disabled(model.progress != nil || model.catchupTarget != nil) }
                }.padding(18)
            } else { ContentUnavailableView("選擇交易商品",systemImage:"chart.xyaxis.line",description:Text("請先從行情頁選擇商品")) }
        }.navigationTitle("交易").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$order){NavigationStack{OrderForm()}}
            .sheet(isPresented:$details){NavigationStack{InstrumentDetails()}}
            .sheet(isPresented:$drawing){NavigationStack{DrawingEditor()}}
            .sheet(isPresented:$alert){NavigationStack{AlertEditor()}}
            .fullScreenCover(isPresented:$fullscreen){VStack{HStack{Text(model.selected?.name ?? "").font(.headline);Spacer();Button("完成"){fullscreen=false}}.padding();ChartView(indicator:indicator,period:period,line:line)}.background(Color(.systemBackground))}
            .task(id:model.selectedID){if let p=model.state?.chartPreferences?[model.selectedID]{indicator=p.indicator;period=p.period;line=p.line;model.interval=p.interval};await model.loadChart()}
            .onChange(of:indicator){_,_ in Task{await model.saveChartPreferences(indicator:indicator,period:period,line:line)}}
            .onChange(of:period){_,_ in Task{await model.saveChartPreferences(indicator:indicator,period:period,line:line)}}
            .onChange(of:line){_,_ in Task{await model.saveChartPreferences(indicator:indicator,period:period,line:line)}}
    }
}
struct BookSide: View {
    var title: String
    var levels: [Level]
    var color: Color
    var body: some View {
        VStack(spacing:7){HStack{Text(title);Spacer();Text("數量")}.font(.caption).foregroundStyle(.secondary)
            if levels.isEmpty{Text("未提供").foregroundStyle(.secondary).font(.caption)}
            ForEach(Array(levels.prefix(5).enumerated()),id:\.offset){_,level in HStack{Text(level.price.description).foregroundStyle(color);Spacer();Text(level.quantity.description)}.font(.system(.caption,design:.monospaced)).lineLimit(1).minimumScaleFactor(0.5)}
        }.frame(maxWidth:.infinity)
    }
}
struct OrderForm: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var side=Side.buy
    @State private var kind=OrderKind.limit
    @State private var price=""
    @State private var quantity="1"
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
    @State private var confirm=false
    @State private var sending=false
    @State private var submitted=false
    @State private var requestID=UUID().uuidString
    @State private var ocoRequestID=UUID().uuidString
    var body: some View {
        Form {
            if let i=model.selected {
                Section("\(i.name) · 本機模擬委託") {
                    Picker("方向",selection:$side){ForEach(Side.allCases,id:\.self){Text($0.label)}}.pickerStyle(.segmented)
                    Picker("委託類型",selection:$kind){ForEach(OrderKind.allCases,id:\.self){Text($0.label)}}.accessibilityIdentifier("orderKind")
                    if [.limit,.stopLimit].contains(kind){TextField("限價",text:$price).keyboardType(.decimalPad)}
                    if kind.conditional && kind != .trailing{TextField("觸發價",text:$trigger).keyboardType(.decimalPad)}
                    if kind == .trailing{TextField("距離／比例（0.05＝5%）",text:$distance).keyboardType(.decimalPad);Toggle("使用百分比",isOn:$trailingPercent)}
                    if kind.conditional{Picker("觸發依據",selection:$reference){ForEach(TriggerReference.allCases,id:\.self){Text($0.rawValue)}}}
                    TextField("數量",text:$quantity).keyboardType(.decimalPad).accessibilityIdentifier("orderQuantity")
                    HStack{ForEach([25,50,75,100],id:\.self){percent in Button("\(percent)%"){setProportion(percent)}.font(.caption).buttonStyle(.borderless)}}
                    Picker("有效期限",selection:$tif){ForEach(TimeInForce.allCases,id:\.self){Text($0.rawValue)}}
                    if tif == .GTD{DatePicker("到期",selection:$expiry,in:Date()...)}
                    Toggle("Post-only（避免吃單）",isOn:$postOnly)
                    Toggle("Reduce-only（僅減倉）",isOn:$reduceOnly)
                }
                if i.asset.derivative {
                    Section("合約風險") {
                        Stepper("槓桿 \(leverage)×",value:$leverage,in:1...i.rules.maxLeverage)
                        Picker("保證金模式",selection:$margin){Text("逐倉").tag(MarginMode.isolated);Text("全倉（同幣別）").tag(MarginMode.cross)}
                        Text("合約名目本金不是帳戶資產。全倉僅共用目前帳戶、相同結算幣別抵押。").font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("本機條件保護") {
                    Picker("保護關聯",selection:$protection){Text("無").tag("無");Text("括號（主單成交後保護）").tag("括號");Text("OCO（兩張退出委託）").tag("OCO")}
                    if protection != "無"{TextField("停利價",text:$profit).keyboardType(.decimalPad);TextField("停損價",text:$stop).keyboardType(.decimalPad)}
                    Text("條件單只在引擎有有效資料且獲得執行時間時監控；A 不補造未監控期間的成交。").font(.caption).foregroundStyle(.secondary)
                }
                Section("預估與可用額") {
                    LabeledContent("\(i.currency) 可用資金",value:model.money(try? model.state.map{try TradingEngine.available($0,currency:i.currency)}))
                    LabeledContent("價格最小跳動",value:i.rules.tick.description)
                    LabeledContent("數量級距",value:i.rules.quantityStep.description)
                    if let preview=preview { LabeledContent("預估名目金額",value:preview.0.description);LabeledContent("預估費用（未含稅）",value:preview.1.description);if i.asset.derivative{LabeledContent("預估初始保證金",value:preview.2.description)} }
                    Text("實際成交依有效買賣盤及價格保護，可能部分成交或保留。規則：\(i.rules.version)").font(.caption)
                }
                Section{Button(sending ? "送出中…":"檢查並送出模擬委託"){confirm=true}.font(.headline).disabled(sending || submitted || model.interactionBlocked).accessibilityIdentifier("submitOrder")}
            }
        }.disabled(sending).interactiveDismissDisabled(sending).overlay(alignment:.bottomLeading){UITestProbe()}.navigationTitle("模擬下單").toolbar{
                ToolbarItem(placement:.topBarLeading){UITestCatchupControl()}
                ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}.disabled(sending)}
            }
            .onAppear{price=model.quote?.last.description ?? ""}
            .alert("確認本機模擬委託",isPresented:$confirm){Button("確認送出"){Task{await send()}};Button("取消",role:.cancel){}}message:{Text("\(model.selected?.symbol ?? "") · \(side.label) · \(quantity)\n不會向交易所傳送委託。")}
    }
    var preview: (Amount,Amount,Amount)? {
        guard let i=model.selected,let q=try? Amount(quantity),let p=(try? Amount(price)) ?? model.quote?.last else{return nil}
        return try? {let notional=try q*p*i.rules.multiplier;return (notional,try i.rules.fees.cumulative(notional:notional,maker:postOnly),try notional/Amount(leverage))}()
    }
    func setProportion(_ percent: Int) {
        guard let i=model.selected,let s=model.state else{return}
        do {
            let ratio=try Amount(percent)/Amount(100)
            if side == .sell { quantity=try ((s.positions[i.id]?.quantity.magnitude ?? .zero)*ratio).description }
            else if let p=model.quote?.last,p > .zero {
                let raw=try TradingEngine.available(s,currency:i.currency)*ratio/Amount("1.06")/p/i.rules.multiplier
                let units=try (raw/i.rules.quantityStep).rounded(0,.down);quantity=try (units*i.rules.quantityStep).description
            }
        }catch{model.error=error.localizedDescription}
    }
    func send() async {
        guard !sending,!submitted,!model.interactionBlocked,let i=model.selected else{return}
        sending=true;defer{sending=false}
        do {
            var r=OrderRequest(instrumentID:i.id,side:side,kind:kind,quantity:try Amount(quantity),price:[.limit,.stopLimit].contains(kind) ? try Amount(price):nil,trigger:kind.conditional && kind != .trailing ? try Amount(trigger):nil)
            r.requestID=requestID
            r.timeInForce=tif;r.expiresAt=tif == .GTD ? Int64(expiry.timeIntervalSince1970):nil;r.postOnly=postOnly;r.reduceOnly=reduceOnly;r.leverage=leverage;r.marginMode=margin;r.triggerReference=reference
            if kind == .trailing{r.trailingDistance=try Amount(distance);r.trailingPercent=trailingPercent}
            if protection == "括號"{r.bracketProfit=try Amount(profit);r.bracketStop=try Amount(stop)}
            let accepted:Bool
            if protection == "OCO"{
                r.kind = .takeProfit;r.trigger=try Amount(profit);r.price=nil;r.reduceOnly=true
                var second=OrderRequest(instrumentID:i.id,side:side,kind:.stopMarket,quantity:r.quantity,trigger:try Amount(stop));second.requestID=ocoRequestID;second.reduceOnly=true;second.leverage=leverage;second.marginMode=margin
                accepted=await model.submit(r,oco:second)
            }else{accepted=await model.submit(r)}
            if accepted{submitted=true;dismiss();model.tab=3}
        }catch{model.error=error.localizedDescription}
    }
}
struct InstrumentDetails: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View { Form{if let i=model.selected{LabeledContent("商品 ID",value:i.id);LabeledContent("類別",value:i.asset.label);LabeledContent("報價幣別",value:i.currency);LabeledContent("交易時區",value:i.rules.timeZone);LabeledContent("合約乘數",value:i.rules.multiplier.description);LabeledContent("規則版本",value:i.rules.version);Text(i.rules.source);Text(i.rules.verifiedAt == nil ? "規則尚未完成官方現行制度核驗，不宣稱符合所有交易所制度。":"規則已記錄核驗時間").foregroundStyle(.orange);NavigationLink("自訂規則／費率／交割"){RuleEditor()};if let q=model.quote{Text(q.coverage);LabeledContent("標記價",value:q.mark?.description ?? "未提供")}}}.navigationTitle("商品規格").toolbar{Button("完成"){dismiss()}} }
}
