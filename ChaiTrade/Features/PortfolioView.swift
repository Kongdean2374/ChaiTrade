import SwiftUI
import Charts
import ChaiTradeCore

struct OrdersView: View {
    @EnvironmentObject var model: AppModel
    @State private var openOnly=true
    @State private var amendment: Order?
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
            if orders.isEmpty{ContentUnavailableView("沒有符合條件的委託",systemImage:"tray",description:Text("已成交、撤單與到期紀錄會保留在歷史中。"))}
            Section("最近成交（模擬）") {
                ForEach(Array((model.state?.fills ?? []).suffix(100).reversed())){fill in
                    VStack(alignment:.leading,spacing:4){Text("\(fill.instrumentID) · \(fill.side.label)").font(.caption.bold());Text("\(fill.quantity) @ \(fill.price) · 費 \(fill.fee) 稅 \(fill.tax)").font(.caption.monospaced());Text("\(fill.source) · \(fill.grade.rawValue)\(fill.estimatedExecution ? " · 估算成交":"")").font(.caption2).foregroundStyle(.secondary)}
                }
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
    var body: some View { Form{Section("新增本機檢討"){TextField("策略／情緒標籤",text:$tags);TextEditor(text:$text).frame(minHeight:120);Button("保存日誌"){Task{guard let engine=model.engine,let context=model.context,!text.isEmpty else{return};await model.run{try await engine.recordJournal(JournalEntry(text:text,tags:tags,time:model.now),context:context)};if model.error == nil{text="";tags=""}}}};ForEach(Array((model.state?.journals ?? []).reversed())){entry in Section(entry.tags){Text(entry.text);Text(Date(timeIntervalSince1970:TimeInterval(entry.time)).formatted()).font(.caption).foregroundStyle(.secondary)}}}.navigationTitle("交易日誌").toolbar{Button("完成"){dismiss()}} }
}
struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    var body: some View {
        List{if let s=model.state{
            Section("口徑：加權平均成本；損益依幣別分開"){
                LabeledContent("成交筆數",value:String(s.fills.count))
                ForEach(s.cash.keys.sorted(),id:\.self){currency in
                    let fills=s.fills.filter{fill in s.instruments.first(where:{$0.id==fill.instrumentID})?.currency==currency}
                    LabeledContent("\(currency) 毛價差",value:(try? sum(fills.map(\.realized)).description) ?? "計算失敗")
                    LabeledContent("\(currency) 費用",value:(try? sum(fills.map(\.fee)).description) ?? "計算失敗")
                    LabeledContent("\(currency) 稅費",value:(try? sum(fills.map(\.tax)).description) ?? "計算失敗")
                }
            }
            Section("資金流調整績效"){
                let nav=Analytics.timeWeighted(s.equity)
                LabeledContent("單位淨值",value:nav.last.flatMap{$0}.map{String(format:"%.6f",$0)} ?? "估值樣本不足")
                LabeledContent("最大回撤（扣除資金流）",value:Analytics.maximumDrawdown(nav).map{String(format:"%.2f%%",$0*100)} ?? "估值樣本不足")
                Chart(Array(nav.enumerated()),id:\.offset){idx,value in if let value{LineMark(x:.value("估值序號",idx),y:.value("單位淨值",value)).foregroundStyle(.orange)}}.frame(height:180)
                Text("缺價與缺匯率區段保留空缺。沒有有效的完整估值時，不顯示虛構報酬率。").font(.caption).foregroundStyle(.secondary)
            }
        }}.navigationTitle("績效分析").toolbar{Button("完成"){dismiss()}}
    }
}
