import SwiftUI
import Charts
import ChaiTradeCore

struct OrdersView: View {
    @EnvironmentObject var model: AppModel
    @State private var openOnly=true
    @State private var amendment: Order?
    @State private var historical: [FillPageRow]=[]
    @State private var historyCursor: Int64?
    @State private var olderOrders:[Order]=[]
    @State private var orderCursor:Int64?
    @State private var orderCursorID:String?
    @State private var search=""
    var orders: [Order] { (model.state?.orders.values.sorted{($0.createdAt,$0.id)>($1.createdAt,$1.id)} ?? []).filter{!openOnly || $0.status.open} }
    var body: some View {
        List {
            Toggle("只看未完成",isOn:$openOnly)
            ForEach(orders){order in
                VStack(alignment:.leading,spacing:7) {
                    HStack{Text(order.request.instrumentID).font(.subheadline.bold());Spacer();Text(order.status.rawValue).font(.caption).foregroundStyle(.orange)}
                    Text("\(order.request.side.label) · \(order.request.kind.label) · \(order.request.timeInForce.rawValue)").font(.caption)
                    HStack{Text("\(order.filled) / \(order.request.quantity)");Spacer();Text("@ \(order.request.price?.description ?? "市價")")}.monospacedDigit()
                    if let reason=order.suspension{Text(reason).font(.caption).foregroundStyle(.orange)}
                    if order.request.kind.conditional{Text("\(order.triggered ? "已觸發":"監控中") · \(order.request.triggerReference.rawValue) · \(order.request.trigger?.description ?? "移動極值")").font(.caption).foregroundStyle(.secondary)}
                    if order.status.open{
                        HStack{Button("撤單",role:.destructive){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.cancel(id:order.id,time:model.now,context:context)}}};Spacer();Button("修改價格／數量"){amendment=order}}.buttonStyle(.borderless).font(.caption)
                    }
                }.padding(.vertical,5)
            }
            if !openOnly{
                ForEach(olderOrders){o in Text("\(o.request.instrumentID) · \(o.request.side.label) · \(o.status.rawValue)\n\(o.filled) / \(o.request.quantity)").font(.caption.monospaced())}
                TextField("歷史商品代碼",text:$search).onChange(of:search){_,_ in olderOrders=[];orderCursor=nil;orderCursorID=nil}
                Button("查詢／載入歷史委託"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{let rows=try await engine.orderPage(limit:100,before:orderCursor,beforeID:orderCursorID,search:search,context:context);let known=Set(orders.map(\.id)+olderOrders.map(\.id));olderOrders=Array((olderOrders+rows.filter{!known.contains($0.id)}).suffix(500));orderCursor=rows.last?.updatedAt;orderCursorID=rows.last?.id;if rows.isEmpty{model.notice="已到符合條件的最早委託"}}}}
            }
            if orders.isEmpty{ContentUnavailableView("沒有符合條件的委託",systemImage:"tray",description:Text("已成交、撤單與到期紀錄會保留在歷史中。"))}
            Section("最近成交（模擬）") {
                ForEach(Array((model.state?.fills ?? []).suffix(100).reversed())){fill in
                    VStack(alignment:.leading,spacing:4){Text("\(fill.instrumentID) · \(fill.side.label)").font(.caption.bold());Text("\(fill.quantity) @ \(fill.price) · 費 \(fill.fee) 稅 \(fill.tax)").font(.caption.monospaced());Text("\(fill.source) · \(fill.grade.rawValue)\(fill.estimatedExecution ? " · 估算成交":"")").font(.caption2).foregroundStyle(.secondary)}
                }
            }
            Section("較早成交（依載入時點分頁）"){
                ForEach(historical){row in let f=row.fill;Text("\(f.instrumentID) · \(f.side.label)\n\(f.quantity) @ \(f.price) · \(f.source)").font(.caption.monospaced())}
                Button("載入較早成交"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{
                    if historyCursor == nil{historyCursor=try await engine.fillPage(limit:100,before:nil,context:context).last?.cursor}
                    guard let cursor=historyCursor else{return}
                    let rows=try await engine.fillPage(limit:100,before:cursor,context:context)
                    historical=Array((historical+rows).suffix(500));historyCursor=rows.last?.cursor ?? cursor
                    if rows.isEmpty{model.notice="已到最早成交紀錄"}
                }}}
            }
        }.navigationTitle("委託與成交").sheet(item:$amendment){o in NavigationStack{AmendView(order:o)}}
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
struct PortfolioView: View {
    @EnvironmentObject var model: AppModel
    @State private var cash=false
    @State private var journal=false
    @State private var performance=false
    var body: some View {
        List {
            Section("\(model.state?.baseCurrency ?? "") 估值") {
                LabeledContent("\(model.valuation?.complete == true ? "淨值":"已知部分資產")",value:model.money(model.valuation?.total))
                LabeledContent("交易淨損益（扣除外部資金流）",value:model.money(model.valuation?.tradingPnL))
                if let v=model.valuation,!v.complete{Text(v.missing.joined(separator:"\n")).font(.caption).foregroundStyle(.orange)}
            }
            Section("幣別餘額") {
                ForEach((model.state?.cash.keys.sorted() ?? []),id:\.self){currency in
                    VStack(alignment:.leading,spacing:5){LabeledContent(currency,value:model.money(model.state?.cash[currency]));Text("可用 \(model.money(try? model.state.map{try TradingEngine.available($0,currency:currency)})) · 淨資金流 \(model.money(model.state?.netFlows[currency]))").font(.caption).foregroundStyle(.secondary)}
                }
                Button("調整虛擬資金／換匯"){cash=true}
            }
            Section("部位與成本") {
                ForEach((model.state?.positions.values.sorted{$0.id<$1.id} ?? []).filter{$0.quantity != .zero}){p in
                    VStack(alignment:.leading,spacing:7){Text(p.id).font(.headline);HStack{Metric(title:"數量",value:p.quantity.description);Metric(title:"平均成本",value:p.average.description);Metric(title:"已實現毛損益",value:p.realized.description)}
                        HStack{Text("保證金 \(p.margin) · \(p.marginMode.rawValue) · \(p.leverage)×").font(.caption).foregroundStyle(.secondary);Spacer();Button("交易／平倉"){if let i=model.state?.instruments.first(where:{$0.id==p.id}){model.select(i)}}.font(.caption).buttonStyle(.borderless)}
                    }.padding(.vertical,6)
                }
            }
            Section{Button("績效與資金流分析"){performance=true};NavigationLink("帳務、交割與市場事件"){AccountingToolsView()};Button("本機交易日誌"){journal=true};Button("匯出成交 CSV"){Task{await model.export(kind:"CSV")}};Button("匯出資金帳本 CSV"){Task{await model.export(kind:"ledger")}};Button("匯出 JSON"){Task{await model.export(kind:"JSON")}}}
            Section{Button("匯出完整委託 CSV"){Task{await model.export(kind:"orders")}}}
            Section("最近資金帳本"){
                ForEach(Array((model.state?.ledger ?? []).suffix(40).enumerated()),id:\.offset){_,entry in HStack{VStack(alignment:.leading){Text(entry.account).font(.caption);Text(entry.currency).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(entry.amount.description).font(.caption.monospaced())}}
            }
        }.navigationTitle("資產").sheet(isPresented:$cash){NavigationStack{CashView()}}.sheet(isPresented:$journal){NavigationStack{JournalView()}}.sheet(isPresented:$performance){NavigationStack{PerformanceView()}}
    }
}
struct CashView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var currency="TWD"
    @State private var amount=""
    @State private var action="入金"
    @State private var destination="USD"
    @State private var rate=""
    @State private var confirm=false
    var body: some View {
        Form {
            Text("這是虛擬資金調整。加錢不算獲利；減資不得動用凍結資金。換匯採明示的自訂模擬匯率，不宣稱真實銀行成交。").font(.footnote)
            Picker("操作",selection:$action){Text("入金").tag("入金");Text("減資").tag("減資");Text("換匯").tag("換匯")}
            TextField("幣別代碼",text:$currency).textInputAutocapitalization(.characters)
            TextField("金額",text:$amount).keyboardType(.decimalPad)
            if action == "換匯"{TextField("目標幣別",text:$destination).textInputAutocapitalization(.characters);TextField("每 1 來源幣可換多少目標幣",text:$rate).keyboardType(.decimalPad)}
            Button("確認虛擬資金操作"){confirm=true}
        }.navigationTitle("資金操作").toolbar{Button("完成"){dismiss()}}
            .confirmationDialog("確認調整目前帳戶的虛擬資金？",isPresented:$confirm,titleVisibility:.visible){Button("確認"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{
                let input=try Amount(amount);guard input > .zero else{throw TradeError.invalid("金額必須大於零")}
                if action == "換匯"{try await engine.exchange(from:currency,to:destination,amount:input,rate:Amount(rate),time:model.now,context:context)}else{try await engine.cashFlow(currency:currency,amount:action == "減資" ? input.negated:input,time:model.now,context:context)}
            };if model.error == nil{dismiss()}}}}
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
    var body: some View {
        Form{
            Section("新增本機檢討"){
                TextField("策略／原因標籤",text:$tags)
                TextField("情緒與執行評價",text:$emotion)
                TextField("關聯委託 ID（可留空）",text:$orderID).textInputAutocapitalization(.never)
                TextEditor(text:$text).frame(minHeight:120).accessibilityIdentifier("journalText")
                if model.journalScreenshot != nil{Toggle("附加剛擷取的本機圖表",isOn:$attach).accessibilityIdentifier("attachJournalChart")}
                if attach,let data=model.journalScreenshot,let image=UIImage(data:data){Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:220).accessibilityLabel("待儲存的模擬圖表").accessibilityIdentifier("journalChartPreview")}
                Button("保存日誌"){
                    Task{guard let engine=model.engine,let context=model.context,!text.isEmpty else{return};await model.run{
                        var entry=JournalEntry(text:text,tags:tags,time:model.now)
                        entry.emotion=emotion;entry.orderID=orderID.isEmpty ? nil:orderID;entry.instrumentID=model.selectedID.isEmpty ? nil:model.selectedID
                        entry.screenshot=attach ? model.journalScreenshot:nil
                        try await engine.recordJournal(entry,context:context)
                    };if model.error==nil{text="";tags="";emotion="";orderID="";attach=false;model.journalScreenshot=nil}}
                }
            }
            ForEach(Array((model.state?.journals ?? []).reversed())){entry in
                Section(entry.tags){
                    Text(entry.text)
                    if let emotion=entry.emotion,!emotion.isEmpty{Text(emotion).font(.caption)}
                    if let id=entry.orderID{Text("委託 \(id)").font(.caption.monospaced()).textSelection(.enabled)}
                    if let data=entry.screenshot,let image=UIImage(data:data){Text("已附模擬圖表").font(.caption);Image(uiImage:image).resizable().scaledToFit().accessibilityLabel("已儲存的模擬圖表").accessibilityIdentifier("savedJournalChart");Button("匯出這張模擬圖表"){model.exportDocument=ExportDocument(data:data);model.exportName="ChaiTrade-模擬交易-\(model.settings.activeMode.accountID).png";model.exporting=true}}
                    Text(Date(timeIntervalSince1970:TimeInterval(entry.time)).formatted()).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.overlay(alignment:.bottomLeading){UITestProbe()}.navigationTitle("交易日誌").toolbar{Button("完成"){dismiss()}}
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
            if !contracts{LabeledContent("現貨成交金額",value:total.notional.description)}
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
