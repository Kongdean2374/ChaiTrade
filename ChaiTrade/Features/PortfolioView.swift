import SwiftUI
import Charts
import ChaiTradeCore

private extension OrderStatus{
    var displayName:String{switch self{case .working:"委託中";case .partiallyFilled:"部分成交";case .filled:"全部成交";case .cancelled:"已撤銷";case .expired:"已到期"}}
}
struct OrdersView:View{
    @EnvironmentObject var model:AppModel
    @State private var openOnly=true
    @State private var allMarkets=false
    @State private var amendment:Order?
    @State private var historical:[FillPageRow]=[]
    @State private var historyCursor:Int64?
    @State private var olderOrders:[Order]=[]
    @State private var orderCursor:Int64?
    @State private var orderCursorID:String?
    @State private var search=""
    private func instrument(_ id:String)->Instrument?{model.state?.instruments.first{$0.id==id}}
    private func matches(_ id:String)->Bool{allMarkets || instrument(id)?.market==model.market}
    private var orders:[Order]{(model.state?.orders.values.sorted{($0.createdAt,$0.id)>($1.createdAt,$1.id)} ?? []).filter{(!openOnly || $0.status.open) && matches($0.request.instrumentID)}}
    var body:some View{List{
        Section{
            Picker("狀態",selection:$openOnly){Text("未完成").tag(true);Text("全部／歷史").tag(false)}.pickerStyle(.segmented)
            Toggle("顯示帳戶所有市場",isOn:$allMarkets)
            Text(allMarkets ? "所有市場共用這個帳戶；其他市場的委託也可在此撤銷。":model.market.label+"委託與成交；切換市場不會移動資金。").font(.caption).foregroundStyle(.secondary)
        }
        if orders.isEmpty{ContentUnavailableView("目前沒有符合的委託",systemImage:"tray",description:Text("送出後可在此查看等待、部分成交、成交與撤銷狀態。"))}
        ForEach(orders){order in orderRow(order)}
        if !openOnly{Section("歷史委託"){
            ForEach(olderOrders.filter{matches($0.request.instrumentID)}){order in orderRow(order)}
            TextField("歷史商品代碼",text:$search).onChange(of:search){_,_ in olderOrders=[];orderCursor=nil;orderCursorID=nil}
            Button("查詢／載入歷史委託"){Task{await loadOrders()}}
        }}
        Section("最近成交（模擬）"){
            let fills=(model.state?.fills ?? []).filter{matches($0.instrumentID)}
            if fills.isEmpty{Text("目前沒有成交紀錄").foregroundStyle(.secondary)}
            ForEach(Array(fills.suffix(100).reversed())){fill in fillRow(fill)}
        }
        Section("較早成交"){
            ForEach(historical.filter{matches($0.fill.instrumentID)}){row in fillRow(row.fill)}
            Button("載入較早成交"){Task{await loadFills()}}
        }
        Section{Text("已到委託頁底部").font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("ordersBottom")}
    }.navigationTitle("委託與成交").sheet(item:$amendment){order in NavigationStack{AmendView(order:order)}}}
    private func orderRow(_ order:Order)->some View{
        let i=instrument(order.request.instrumentID)
        return VStack(alignment:.leading,spacing:9){
            HStack{VStack(alignment:.leading,spacing:4){Text(i?.name ?? order.request.instrumentID).font(.headline);Text((i?.symbol ?? order.request.instrumentID)+" · "+(i?.identity?.exchange ?? "")).font(.caption).foregroundStyle(.secondary)};Spacer();Text(order.status.displayName).font(.caption.weight(.semibold)).foregroundStyle(.orange)}
            Text((order.request.side == .buy ? i?.buyLabel:i?.sellLabel ?? "賣出") ?? "買入").font(.subheadline)
            HStack{Text(order.request.kind.label+" · "+order.request.timeInForce.rawValue);Spacer();Text(MarketText.number(order.filled)+" / "+MarketText.number(order.request.quantity)+(i?.quantityUnit ?? ""))}.font(.caption).monospacedDigit()
            LabeledContent("委託價格",value:order.request.price.map{MarketText.number($0)} ?? "市價").font(.caption)
            if let reason=order.suspension{Text(reason).font(.caption).foregroundStyle(.orange)}
            if order.request.kind.conditional{Text((order.triggered ? "已觸發":"監控中")+" · "+(order.request.trigger?.description ?? "移動極值")).font(.caption).foregroundStyle(.secondary)}
            if order.status.open{HStack{Button("撤單",role:.destructive){Task{guard let engine=model.engine,let context=model.context else{return};_ = await model.run{try await engine.cancel(id:order.id,time:model.now,context:context)}}};Spacer();Button("修改價格／數量"){amendment=order}}.buttonStyle(.borderless).font(.subheadline).disabled(model.interactionBlocked)}
        }.padding(.vertical,6)
    }
    private func fillRow(_ fill:Fill)->some View{
        let i=instrument(fill.instrumentID)
        let direction=fill.side == .buy ? (i?.buyLabel ?? "買入"):(i?.sellLabel ?? "賣出")
        let title="\(i?.name ?? fill.instrumentID) · \(direction)"
        let execution="\(MarketText.number(fill.quantity))\(i?.quantityUnit ?? "") @ \(MarketText.number(fill.price)) \(i?.currency ?? "")"
        let fees="費用 \(MarketText.number(fill.fee)) · 稅 \(MarketText.number(fill.tax))"
        let time=Date(timeIntervalSince1970:TimeInterval(fill.time)).formatted()
        let explanation=fill.estimatedExecution ? "參考價估算成交":"本機撮合成交"
        return VStack(alignment:.leading,spacing:7){
            Text(title).font(.subheadline.bold())
            Text(execution).font(.subheadline.monospacedDigit())
            Text(fees).font(.caption)
            Text(time+" · "+explanation).font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func loadOrders()async{
        guard let engine=model.engine,let context=model.context else{return}
        _ = await model.run{let rows=try await engine.orderPage(limit:100,before:orderCursor,beforeID:orderCursorID,search:search,context:context);let known=Set(orders.map(\.id)+olderOrders.map(\.id));olderOrders=Array((olderOrders+rows.filter{!known.contains($0.id)}).suffix(500));orderCursor=rows.last?.updatedAt;orderCursorID=rows.last?.id;if rows.isEmpty{model.notice="已到符合條件的最早委託"}}
    }
    private func loadFills()async{
        guard let engine=model.engine,let context=model.context else{return}
        _ = await model.run{if historyCursor==nil{historyCursor=try await engine.fillPage(limit:100,before:nil,context:context).last?.cursor};guard let cursor=historyCursor else{return};let rows=try await engine.fillPage(limit:100,before:cursor,context:context);historical=Array((historical+rows).suffix(500));historyCursor=rows.last?.cursor ?? cursor;if rows.isEmpty{model.notice="已到最早成交紀錄"}}
    }
}
struct AmendView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    let order: Order
    @State private var quantity=""
    @State private var price=""
    var body: some View {
        Form{Text("資金檢查失敗時維持原委託；改單會保存修訂並重新排序。").font(.footnote);TextField("新委託總量（含已成交）",text:$quantity).keyboardType(.decimalPad);if order.request.price != nil{TextField("新價格",text:$price).keyboardType(.decimalPad)};Button("確認改單"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.amend(id:order.id,quantity:Amount(quantity),price:price.isEmpty ? nil:Amount(price),time:model.now,context:context)};if model.error == nil{dismiss()}}}}.navigationTitle("修改委託").toolbar{Button("取消"){dismiss()}}.onAppear{quantity=order.request.quantity.description;price=order.request.price?.description ?? ""}
    }
}
struct PortfolioView:View{
    @EnvironmentObject var model:AppModel
    @State private var cash=false
    @State private var journal=false
    @State private var performance=false
    private var positions:[Position]{(model.state?.positions.values.sorted{$0.id<$1.id} ?? []).filter{$0.quantity != .zero}}
    var body:some View{ScrollView{VStack(alignment:.leading,spacing:22){
        VStack(alignment:.leading,spacing:8){Text(model.valuation?.complete == true ? "總資產":"已知部分資產").font(.subheadline).foregroundStyle(.secondary);Text(model.money(model.valuation?.total)).font(.largeTitle.bold()).monospacedDigit();Text((model.state?.baseCurrency ?? "")+" · "+(model.state?.mode.label ?? "")).font(.caption).foregroundStyle(.secondary)}
        if let value=model.valuation,!value.complete{MarketCard{Label("估值資料尚未齊全",systemImage:"info.circle").font(.headline);Text(value.missing.joined(separator:"\n")).font(.caption).foregroundStyle(.orange);Text("缺少匯率或價格時只顯示已知部分，不以假匯率合計。").font(.caption).foregroundStyle(.secondary)}}
        MarketCard{MarketSectionTitle(title:"資金與損益");LabeledContent("交易淨損益（扣除外部資金流）",value:model.money(model.valuation?.tradingPnL));ForEach(model.state?.cash.keys.sorted() ?? [],id:\.self){currency in currencySummary(currency)};Button("調整虛擬資金／換匯"){cash=true}}
        HStack{Button("本機交易日誌"){journal=true}.accessibilityIdentifier("openJournal");Spacer();Button("績效與資金流分析"){performance=true}}
            .font(.subheadline).buttonStyle(.bordered)
        MarketCard{MarketSectionTitle(title:"資金曲線",subtitle:"依實際估值事件；缺少資料的區段保留空缺");let points=Analytics.equitySeries(model.state?.equity ?? []);if points.count>=2{Chart(Array(points.suffix(500))){point in LineMark(x:.value("時間",Date(timeIntervalSince1970:TimeInterval(point.time))),y:.value("資產",point.value),series:.value("有效區段",point.segment)).foregroundStyle(.orange)}.frame(height:180)}else{Text("開始交易或推進模擬時間後，可查看已保存的資金變化。每次虛擬增減資金會另外記錄。").font(.subheadline).foregroundStyle(.secondary)}}
        positionSection(derivative:false)
        positionSection(derivative:true)
        MarketCard{MarketSectionTitle(title:"費用與配置",subtitle:"依幣別分開；不使用缺失的匯率合計");let totals=(try? model.state.map{try Analytics.fillTotals($0)}) ?? [:];ForEach(totals.keys.sorted(),id:\.self){currency in if let total=totals[currency]{LabeledContent(currency+"手續費",value:model.money(total.fees));LabeledContent(currency+"交易稅",value:model.money(total.taxes));LabeledContent(currency+"已實現價差",value:model.money(total.realized))}};ForEach(model.state?.cash.keys.sorted() ?? [],id:\.self){currency in let count=positions.filter{position in model.state?.instruments.first{$0.id==position.instrumentKey}?.currency==currency}.count;LabeledContent(currency+"持倉商品",value:"\(count)項")}}
        MarketCard{Button("交易紀錄"){model.tab=3};NavigationLink("帳務、交割與市場事件"){AccountingToolsView()};NavigationLink("資料工具：匯出與帳本"){DataToolsView()}}
        Text("已到資產頁底部").font(.caption2).foregroundStyle(.secondary).frame(maxWidth:.infinity).accessibilityIdentifier("portfolioBottom")
    }.padding(18).padding(.bottom,20)}.background(Color(.systemGroupedBackground)).navigationTitle("資產").sheet(isPresented:$cash){NavigationStack{CashView()}}.sheet(isPresented:$journal){NavigationStack{JournalView()}}.sheet(isPresented:$performance){NavigationStack{PerformanceView()}}}
    private func currencySummary(_ currency:String)->some View{
        let balance=model.state?.cash[currency] ?? .zero
        let available=(try? model.state.map{try TradingEngine.available($0,currency:currency)}) ?? .zero
        let frozen=max(.zero,(try? balance-available) ?? .zero)
        return VStack(alignment:.leading,spacing:10){Text(currency).font(.headline);HStack{Metric(title:"可用資金",value:model.money(available));Metric(title:"凍結／保證金",value:model.money(frozen))};LabeledContent("現金餘額",value:model.money(balance));Divider()}
    }
    @ViewBuilder private func positionSection(derivative:Bool)->some View{
        let rows=positions.filter{p in model.state?.instruments.first{$0.id==p.instrumentKey}?.asset.derivative==derivative}
        MarketCard{MarketSectionTitle(title:derivative ? "合約持倉":"現貨持倉");if rows.isEmpty{Text(derivative ? "目前沒有合約持倉":"目前沒有現貨持倉").font(.subheadline).foregroundStyle(.secondary)};ForEach(rows){position in if let instrument=model.state?.instruments.first(where:{$0.id==position.instrumentKey}){positionRow(position,instrument:instrument)}}}
    }
    private func positionRow(_ p:Position,instrument i:Instrument)->some View{
        VStack(alignment:.leading,spacing:10){HStack{VStack(alignment:.leading){Text(i.name).font(.headline);Text(i.symbol+" · "+i.currency).font(.caption).foregroundStyle(.secondary)};Spacer();Button("交易／平倉"){model.select(i)}.buttonStyle(.bordered).font(.caption)};HStack{Metric(title:"數量（\(i.quantityUnit)）",value:model.money(p.quantity));Metric(title:"平均成本",value:model.money(p.average))};if let q=model.state?.quotes[i.id],let price=i.asset.derivative ? q.mark:q.last{let unrealized=try? (price-p.average)*p.quantity*i.rules.multiplier;LabeledContent("未實現損益（\(i.currency)）",value:model.money(unrealized))}else{Text("缺少有效估值價格").font(.caption).foregroundStyle(.orange)};LabeledContent("已實現價差（未扣費）",value:model.money(p.realized));if i.asset.derivative{Text("\(p.leverage)× · "+(p.side?.label ?? "單向")+" · 保證金 "+model.money(p.margin)).font(.caption).foregroundStyle(.secondary);ContractPositionRiskView(position:p)};Divider()}
    }
}
struct CashView: View {
    var initialCurrency:String?=nil
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var currency="TWD"
    @State private var amount=""
    @State private var action="入金"
    @State private var operationID=UUID().uuidString
    @State private var saving=false
    @State private var destination="USD"
    @State private var rate=""
    @State private var confirm=false
    var body: some View {
        Form {
            Text("這是虛擬資金調整。加錢不算獲利；減資不得動用凍結資金。換匯採明示的自訂模擬匯率，不宣稱真實銀行成交。").font(.footnote)
            Picker("操作",selection:$action){Text("增加虛擬資金").tag("入金");Text("減少虛擬資金").tag("減資");Text("模擬換匯").tag("換匯")}
            TextField("幣別代碼",text:$currency).textInputAutocapitalization(.characters)
            TextField("金額",text:$amount).keyboardType(.decimalPad)
            if action == "換匯"{TextField("目標幣別",text:$destination).textInputAutocapitalization(.characters);TextField("每 1 來源幣可換多少目標幣",text:$rate).keyboardType(.decimalPad)}
            Button("確認虛擬資金操作"){confirm=true}
        }.disabled(saving).interactiveDismissDisabled(saving).navigationTitle("模擬資金操作").toolbar{Button("完成"){dismiss()}.disabled(saving)}.onAppear{currency=initialCurrency ?? model.state?.baseCurrency ?? "TWD"}
            .confirmationDialog("確認調整目前帳戶的虛擬資金？",isPresented:$confirm,titleVisibility:.visible){Button("確認"){
                guard !saving,let engine=model.engine,let context=model.context else{return};saving=true
                Task{defer{saving=false};let success=await model.run{
                    let input=try Amount(amount);guard input > .zero else{throw TradeError.invalid("金額必須大於零")}
                    if action == "換匯"{try await engine.exchange(from:currency,to:destination,amount:input,rate:Amount(rate),time:model.now,eventID:operationID,context:context)}else{try await engine.cashFlow(currency:currency,amount:action == "減資" ? input.negated:input,time:model.now,eventID:operationID,context:context)}
                };if success,model.context==context{dismiss()}}
            } }
    }
}
struct JournalView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var text=""
    @State private var tags=""
    @State private var emotion=""
    @State private var orderID=""
    @State private var attach=false
    @State private var saving=false
    @State private var draftID=UUID().uuidString
    var body: some View {
        Form{
            Section("新增本機檢討"){
                TextField("策略／原因標籤",text:$tags)
                TextField("情緒與執行評價",text:$emotion)
                TextField("關聯委託 ID（可留空）",text:$orderID).textInputAutocapitalization(.never)
                TextEditor(text:$text).frame(minHeight:120).accessibilityIdentifier("journalText")
                if model.journalScreenshot != nil{Toggle("附加剛擷取的本機圖表",isOn:$attach).accessibilityIdentifier("attachJournalChart")}
                if attach,let data=model.journalScreenshot,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:220).accessibilityLabel("待儲存的模擬圖表").accessibilityIdentifier("journalChartPreview")}

            }.disabled(saving || model.interactionBlocked)

            ForEach(Array((model.state?.journals ?? []).reversed())){entry in
                Section(entry.tags){
                    Text(entry.text)
                    if let emotion=entry.emotion,!emotion.isEmpty{Text(emotion).font(.caption)}
                    if let id=entry.orderID{Text("委託 \(id)").font(.caption.monospaced()).textSelection(.enabled)}
                    if let data=entry.screenshot,let image=UIImage(data:data){Text("已附模擬圖表").font(.caption);Image(uiImage:image).resizable().scaledToFit().accessibilityLabel("已儲存的模擬圖表").accessibilityIdentifier("savedJournalChart");Button("匯出這張模擬圖表"){model.exportDocument=ExportDocument(data:data);model.exportName="ChaiTrade-模擬交易-\(model.settings.activeMode.accountID).png";model.exporting=true}}
                    Text(Date(timeIntervalSince1970:TimeInterval(entry.time)).formatted()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.scrollDismissesKeyboard(.immediately).safeAreaInset(edge:.bottom){saveButton.padding(.horizontal,16).padding(.vertical,8).background(.bar)}.interactiveDismissDisabled(saving).presentationDragIndicator(.visible).overlay(alignment:.bottomLeading){UITestProbe()}.modifier(UITestVisualEnvironment()).navigationTitle("交易日誌").toolbar{
            ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}.disabled(saving)}
            ToolbarItemGroup(placement:.keyboard){Spacer();Button("收起鍵盤"){UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}}
        }
    }
    private var saveButton:some View{
        Button(saving ? "保存中…":"保存日誌"){
                    guard !saving,!model.interactionBlocked,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return}
                    saving=true
                    var entry=JournalEntry(id:draftID,text:text,tags:tags,time:model.now)
                    entry.emotion=emotion;entry.orderID=orderID.isEmpty ? nil:orderID;entry.instrumentID=model.selectedID.isEmpty ? nil:model.selectedID
                    let screenshot=attach ? model.journalScreenshot:nil;entry.screenshot=screenshot
                    let intent=entry
                    Task{defer{saving=false};if await model.saveJournal(intent){
                        text="";tags="";emotion="";orderID="";attach=false;draftID=UUID().uuidString
                        if screenshot==model.journalScreenshot{model.journalScreenshot=nil}
                    }}
                }.disabled(saving || model.interactionBlocked || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("saveJournal")
            .font(.headline).frame(maxWidth:.infinity,minHeight:48).buttonStyle(.borderedProminent)
    }
}

struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var report:PerformanceReport?
    @State private var span="全部"
    @State private var date=Date()
    @State private var calculating=false
    @State private var generation=UUID()
    @State private var historicalEquity:[EquityPageRow]=[]
    @State private var equityCursor:Int64?
    var body: some View {
        List{
            Section("歷史成交報表"){
                Picker("期間",selection:$span){ForEach(["全部","日","週","月"],id:\.self){Text($0)}}
                if span != "全部"{DatePicker("日期",selection:$date,in:...Date(timeIntervalSince1970:TimeInterval(model.now)),displayedComponents:.date)}
                Text("期間以 Asia/Taipei 計算；不同幣別分開，不把每次部分成交當獨立勝利。").font(.caption)
                if calculating{ProgressView("逐筆計算歷史成交與周期…")}
                if let report{PerformanceDetails(report:report)}
            }
            if let s=model.state{
            Section("口徑：加權平均成本；損益依幣別分開"){
                LabeledContent("成交筆數",value:String((s.history?.fills ?? 0)+s.fills.count))
                let totals=(try? Analytics.fillTotals(s)) ?? [:]
                ForEach(s.cash.keys.sorted(),id:\.self){currency in
                    let total=totals[currency] ?? FillTotals()
                    LabeledContent("\(currency) 毛價差",value:total.realized.description)
                    LabeledContent("\(currency) 費用",value:total.fees.description)
                    LabeledContent("\(currency) 稅費",value:total.taxes.description)
                }
            }
            Section("資金流調整績效"){
                let nav=Analytics.timeWeighted(s)
                let metrics=Analytics.equityMetrics(s)
                LabeledContent("單位淨值",value:metrics.hasGap ? "歷史資料有缺口":nav.last.flatMap{$0}.map{String(format:"%.6f",$0)} ?? "估值樣本不足")
                LabeledContent("已觀測最大回撤（扣除資金流）",value:metrics.drawdown.map{String(format:"%.2f%%",$0*100)} ?? "估值樣本不足")
                Chart(Array(Analytics.returnSeries(nav).suffix(1000))){point in LineMark(x:.value("估值序號",point.id),y:.value("單位淨值",point.value),series:.value("有效區段",point.segment)).foregroundStyle(.orange)}.frame(height:180)
                Text("圖表只載入最近估值點，累計報酬與回撤保留完整前綴。缺價與缺匯率區段保留空缺；不是完整績效宣告。").font(.caption).foregroundStyle(.secondary)
            }
            Section("歷史淨值分頁（按事件序）"){
                if !historicalEquity.isEmpty{
                    Chart(Array(historicalEquity.reversed())){row in if let value=row.point.value{LineMark(x:.value("時間",Date(timeIntervalSince1970:TimeInterval(row.point.time))),y:.value("歷史淨值",value.displayDouble),series:.value("有效區段",row.metrics.segment)).foregroundStyle(.orange)}}.frame(height:180)
                }
                Button("載入較早淨值區段"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{let rows=try await engine.equityPage(limit:100,before:equityCursor,context:context);historicalEquity=Array((historicalEquity+rows).suffix(1000));equityCursor=rows.last?.cursor ?? equityCursor;if rows.isEmpty{model.notice="已到最早淨值事件"}}}}
            }
        }}.navigationTitle("績效分析").toolbar{Button("完成"){dismiss()}}
            .task{date=Date(timeIntervalSince1970:TimeInterval(model.now));await calculate()}
            .onChange(of:span){_,_ in Task{await calculate()}}
            .onChange(of:date){_,_ in if span != "全部"{Task{await calculate()}}}
    }
    func calculate()async{
        guard let engine=model.engine,let context=model.context else{return}
        let token=UUID();generation=token;calculating=true
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=TimeZone(identifier:"Asia/Taipei")!;calendar.firstWeekday=2
        let component:Calendar.Component=span == "週" ? .weekOfYear:span == "月" ? .month:.day
        let period=calendar.dateInterval(of:component,for:date)!
        let start=span == "全部" ? 0:Int64(period.start.timeIntervalSince1970),end=span == "全部" ? model.now+1:min(model.now+1,Int64(period.end.timeIntervalSince1970))
        do{let result=try await engine.performance(from:start,until:end,context:context);if generation==token{report=result}}
        catch{model.error=error.localizedDescription}
        if generation==token{calculating=false}
    }
}
private struct PerformanceDetails:View{
    @EnvironmentObject var model:AppModel
    let report:PerformanceReport
    var body:some View{
        ForEach(report.currencies.keys.sorted(),id:\.self){currency in
            let total=report.currencies[currency]!,cycles=report.cycles[currency]
            LabeledContent("\(currency) 區間成交筆數",value:String(total.count))
            let contracts=report.instruments.keys.contains{id in model.state?.instruments.contains(where:{$0.id==id && $0.currency==currency && ($0.asset.derivative || $0.rules.multiplier != .one)})==true}
            if total.notionalComplete==true{LabeledContent(contracts ? "名目成交金額":"現貨成交金額",value:MarketText.number(total.notional))}else{Text("舊成交缺少完整歷史乘數，成交金額不完整。").font(.caption).foregroundStyle(.orange)}
            if let net=report.economicNet?[currency]{LabeledContent("含持有現金流的期間淨損益",value:MarketText.number(net))}
            ForEach((report.cashFlows?[currency] ?? [:]).keys.sorted(),id:\.self){kind in LabeledContent(kind,value:MarketText.number(report.cashFlows?[currency]?[kind]))}
            LabeledContent("\(currency) 成交淨損益",value:(try? (total.realized-total.fees-total.taxes).description) ?? "計算失敗")
            LabeledContent("已結束周期（含持平）",value:String(cycles?.closed ?? 0))
            LabeledContent("勝率",value:cycles?.winRate.map{String(format:"%.2f%%",$0*100)} ?? "樣本不足")
            LabeledContent("平均獲利／平均虧損",value:"\(cycles?.averageWin?.description ?? "樣本不足") / \(cycles?.averageLoss?.description ?? "樣本不足")")
            LabeledContent("總獲利／總虧損比",value:cycles?.profitFactor?.description ?? "樣本不足或無虧損")
            LabeledContent("平均持有秒數",value:cycles?.averageHoldingSeconds.map{String(format:"%.0f",$0)} ?? "樣本不足")
        }
        DisclosureGroup("按商品分布"){
            ForEach(report.instruments.keys.sorted(),id:\.self){id in LabeledContent(id,value:"\(report.instruments[id]!.count) 筆 · 毛損益 \(report.instruments[id]!.realized)").font(.caption)}
        }
        Text(report.policy).font(.caption).foregroundStyle(.secondary)
        Button("匯出本期績效 JSON"){do{model.exportDocument=ExportDocument(data:try AccountRepository.encode(report));model.exportName="ChaiTrade-模擬績效-\(report.accountID).json";model.exporting=true}catch{model.error=error.localizedDescription}}
    }
}
