import SwiftUI
import UIKit
import ChaiTradeCore

struct AccountingToolsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        List {
            Section("可追查的帳務操作") {
                NavigationLink("估值匯率與來源"){FXEditor()}
                NavigationLink("股息、分割與商品事件"){CorporateActionEditor()}
                NavigationLink("資金費率／隔夜費與期貨結算"){CarryEditor()}
                NavigationLink("逐倉保證金調整"){MarginEditor()}
            }
            Section("應收應付與交割"){
                Text("只有設定交割營業日的商品使用延後交割；未核驗規則預設明示為自訂模擬即時交割。未結算應付限制可用現金，估值不重複加計。").font(.caption).foregroundStyle(.secondary)
                ForEach(Array((model.state?.lifecycle?.settlements ?? []).reversed())){e in
                    VStack(alignment:.leading,spacing:5){Text("\(e.currency) 應收 \(e.receivable)／應付 \(e.payable)").font(.caption.monospaced());Text("\(Date(timeIntervalSince1970:TimeInterval(e.due)).formatted()) · \(e.completedAt == nil ? "待交割":"已交割")").font(.caption2).foregroundStyle(.secondary)}
                }
            }
            Section("費用與股務紀錄"){
                ForEach(Array((model.state?.lifecycle?.carry ?? []).reversed())){e in Text("\(e.kind) · \(e.instrumentID)\n\(e.rate) × \(e.mark)；費用 \(e.amount)\n\(e.source)").font(.caption)}
                ForEach(Array((model.state?.lifecycle?.actions ?? []).reversed())){e in Text("\(e.kind.rawValue) · \(e.instrumentID) · \(e.source)").font(.caption)}
            }
        }.navigationTitle("帳務與市場事件")
    }
}
struct FXEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var currency="USD"
    @State private var rate=""
    @State private var source="使用者自訂模擬匯率"
    var body: some View {
        Form{
            Text("1 單位來源幣換算為多少 \(model.state?.baseCurrency ?? "TWD")。USDT、USDC 與 USD 分開設定，不固定視為 1:1。人工匯率不宣稱為即時行情，預設24小時後須重新確認；過期不參與總資產換算。").font(.footnote)
            TextField("來源幣別",text:$currency).textInputAutocapitalization(.characters);TextField("換算匯率",text:$rate).keyboardType(.decimalPad);TextField("來源說明",text:$source)
            Button("保存估值匯率"){Task{guard let engine=model.engine,let context=model.context,let base=model.state?.baseCurrency else{return};await model.run{try await engine.setFX(FXRate(currency:currency,base:base,rate:Amount(rate),time:model.now,source:source,kind:context.mode == .offline ? .simulated:.userDefined),context:context)}}}
            ForEach(model.state?.lifecycle?.rates ?? [],id:\.currency){r in Text("\(r.currency)/\(r.base) @ \(r.rate)\n\(r.source) · \(Date(timeIntervalSince1970:TimeInterval(r.time)).formatted())\n"+(r.usable(at:model.now) ? "有效（人工／參考匯率，非保證成交匯率）":"已過期或時間不符，請更新")).font(.caption)}
        }.navigationTitle("估值匯率")
    }
}
struct CorporateActionEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var id=""
    @State private var kind=CorporateActionKind.split
    @State private var ratio="2"
    @State private var amount="1"
    @State private var symbol=""
    @State private var payment=Date().addingTimeInterval(86400)
    @State private var source="使用者人工輸入事件；非官方同步"
    @State private var confirm=false
    var body: some View {
        Form {
            Picker("商品",selection:$id){ForEach((model.state?.instruments ?? []).filter{!$0.asset.derivative && $0.asset != .index}){i in Text(i.name).tag(i.id)}}
            Picker("事件",selection:$kind){Text("分割／反向分割").tag(CorporateActionKind.split);Text("股息／配息").tag(CorporateActionKind.dividend);Text("代碼變更").tag(CorporateActionKind.rename);Text("停牌").tag(CorporateActionKind.halt);Text("恢復交易").tag(CorporateActionKind.resume);Text("現金清算／下市").tag(CorporateActionKind.cashLiquidation)}
            if kind == .split{TextField("每 1 單位換成多少（2＝拆二；0.5＝併二）",text:$ratio).keyboardType(.decimalPad)}
            if kind == .dividend || kind == .cashLiquidation{TextField("每單位金額",text:$amount).keyboardType(.decimalPad)}
            if kind == .dividend{DatePicker("股息入帳時間",selection:$payment)}
            if kind == .rename{TextField("新顯示代碼（穩定 ID 保留）",text:$symbol)}
            TextField("可信來源或人工模擬說明",text:$source)
            Text("以目前帳戶時間套用，事件僅記帳一次。分割調整數量與成本，不重寫過去成交；不合法級距的未完成委託會取消。A 缺少官方事件不會自行猜測補做。").font(.caption)
            Button("檢查並套用帳戶事件"){confirm=true}
        }.navigationTitle("股務與市場事件")
            .onAppear{id=model.state?.instruments.first(where:{!$0.asset.derivative && $0.asset != .index})?.id ?? "";payment=Date(timeIntervalSince1970:TimeInterval(model.now+86400))}
            .confirmationDialog("確認人工事件會影響目前帳戶的持倉與帳務？",isPresented:$confirm,titleVisibility:.visible){Button("確認套用"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{let action=try CorporateAction(instrumentID:id,kind:kind,time:model.now,ratio:kind == .split ? Amount(ratio):nil,cashPerUnit:kind == .dividend || kind == .cashLiquidation ? Amount(amount):nil,paymentTime:kind == .dividend ? Int64(payment.timeIntervalSince1970):nil,newSymbol:kind == .rename ? symbol:nil,source:source);try await engine.corporateAction(action,context:context);try await engine.initializeQuotes(context:context)}}}}
    }
}
struct CarryEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var id=""
    @State private var rate="0.0001"
    @State private var price=""
    @State private var kind="funding"
    @State private var eventID=UUID().uuidString
    @State private var source="使用者自訂模擬費率／結算事件"
    @State private var final=false
    @State private var confirm=false
    var body: some View {
        Form{
            Picker("合約",selection:$id){ForEach((model.state?.instruments ?? []).filter{$0.asset.derivative}){i in Text(i.name).tag(i.id)}}
            Picker("操作",selection:$kind){Text("資金費率").tag("funding");Text("隔夜費／利息").tag("interest");Text("期貨每日／到期結算").tag("settlement")}
            TextField("有效標記／結算價",text:$price).keyboardType(.decimalPad)
            if kind != "settlement"{TextField("本期費率（0.0001＝0.01%）",text:$rate).keyboardType(.numbersAndPunctuation)}else{Toggle("最後到期結算並禁止新倉",isOn:$final)}
            TextField("唯一事件 ID（同 ID 不重複入帳）",text:$eventID).autocorrectionDisabled();TextField("費率／價格來源",text:$source)
            Text("未取得可靠來源的期間費用不會默認為零或猜測補扣。此頁只處理明確輸入的帳戶事件，不能冒充交易所歷史帳單。").font(.caption)
            Button("確認記帳"){confirm=true}
        }.navigationTitle("費用與期貨結算").onAppear{id=model.state?.instruments.first(where:{$0.asset.derivative})?.id ?? ""}
            .confirmationDialog("確認依指定價格與費率記帳？",isPresented:$confirm,titleVisibility:.visible){Button("確認"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{if kind == "settlement"{try await engine.settleFuture(instrumentID:id,price:Amount(price),time:model.now,eventID:eventID,final:final,context:context)}else{try await engine.applyCarry(instrumentID:id,rate:Amount(rate),mark:Amount(price),time:model.now,eventID:eventID,kind:kind,source:source,context:context)}}}}}
    }
}
private struct MarginAdjustmentDraft{
    let position:Position
    let amount:Amount
    let context:AccountContext
    let eventID=UUID().uuidString
}
struct MarginEditor: View {
    var initialPositionID:String?=nil
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var id=""
    @State private var amount=""
    @State private var removing=false
    @State private var saving=false
    @State private var confirming=false
    @State private var draft:MarginAdjustmentDraft?
    private var positions:[Position]{(model.state?.positions.values.sorted{$0.id<$1.id} ?? []).filter{$0.quantity != .zero && $0.marginMode == .isolated && $0.margin > .zero}}
    var body:some View{Form{
        if positions.isEmpty{ContentUnavailableView("目前沒有逐倉合約持倉",systemImage:"chart.line.uptrend.xyaxis")}
        else{Section("選擇部位"){
            Picker("逐倉部位",selection:$id){ForEach(positions){p in Text(positionName(p)).tag(p.id)}}
            if let position=positions.first(where:{$0.id==id}){LabeledContent("目前保證金",value:MarketText.number(position.margin));ContractPositionRiskView(position:position)}
        }
        Section("調整"){
            TextField("調整金額",text:$amount).keyboardType(.decimalPad).accessibilityIdentifier("marginAmount")
            Toggle("移除保證金",isOn:$removing)
            Text("追加只凍結目前帳戶同結算幣別的可用現金，不增加淨值；移除後仍須足以支付維持保證金及預估平倉費用。").font(.caption).foregroundStyle(.secondary)
            Button(saving ? "調整中…":"檢查保證金調整"){prepare()}.disabled(saving || model.interactionBlocked).accessibilityIdentifier("reviewMarginAdjustment")
        }}
    }.disabled(saving).scrollDismissesKeyboard(.interactively).navigationTitle("調整逐倉保證金").interactiveDismissDisabled(saving)
        .onAppear{if id.isEmpty{id=initialPositionID ?? positions.first?.id ?? ""}}
        .confirmationDialog("確認本機保證金調整？",isPresented:$confirming,titleVisibility:.visible){Button("確認調整"){submit()};Button("取消",role:.cancel){draft=nil}}message:{if let draft{Text(positionName(draft.position)+"\n調整 "+MarketText.number(draft.amount)+"；不會轉出資金。")}}
    }
    private func positionName(_ position:Position)->String{
        let name=model.state?.instruments.first{$0.id==position.instrumentKey}?.name ?? position.instrumentKey
        return name+" · "+(position.quantity > .zero ? "多倉":"空倉")
    }
    private func prepare(){
        guard !saving,let position=positions.first(where:{$0.id==id}),let context=model.context else{return}
        do{let input=try Amount(amount);guard input > .zero else{throw TradeError.invalid("金額需大於零")};draft=MarginAdjustmentDraft(position:position,amount:removing ? input.negated:input,context:context);UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil);confirming=true}catch{model.error=error.localizedDescription}
    }
    private func submit(){
        guard !saving,let intent=draft,let engine=model.engine,model.context==intent.context else{return};saving=true
        Task{defer{saving=false;draft=nil};let success=await model.run{try await engine.adjustMargin(instrumentID:intent.position.instrumentKey,amount:intent.amount,time:model.now,positionSide:intent.position.side,eventID:intent.eventID,context:intent.context)};if success,model.context==intent.context{dismiss()}}
    }
}
struct RuleEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var tick=""
    @State private var step=""
    @State private var multiplier=""
    @State private var maker=""
    @State private var taker=""
    @State private var fixed=""
    @State private var minimum=""
    @State private var tax=""
    @State private var zone="UTC"
    @State private var open=0
    @State private var close=1440
    @State private var weekdays=false
    @State private var days=0
    @State private var holidays=""
    @State private var expiry=Date().addingTimeInterval(2592000)
    @State private var scheduledCarry=false
    @State private var carryHours=8
    @State private var carryOffset=0
    @State private var longCarry="0.0001"
    @State private var shortCarry="-0.0001"
    @State private var dailySettlement=false
    @State private var settlementMinute=0
    var body: some View {
        Form{
            Text("自訂模擬規則，不代表交易所已核驗制度。商品有持倉或未完成委託時禁止直接更改規格，避免回頭重寫歷史。").font(.footnote).foregroundStyle(.orange)
            Section("價格與數量"){TextField("最小跳動",text:$tick);TextField("數量級距",text:$step);TextField("合約乘數",text:$multiplier)}.keyboardType(.decimalPad)
            if model.selected?.asset.derivative==true{NavigationLink("階梯保證金與抵押折扣"){ContractRiskRulesView()}}
            Section("每委託累計費用"){TextField("Maker 比例費率",text:$maker);TextField("Taker 比例費率",text:$taker);TextField("固定費",text:$fixed);TextField("最低手續費",text:$minimum);TextField("賣出稅率",text:$tax)}.keyboardType(.decimalPad)
            Section("交易日曆與交割"){
                Picker("IANA 時區",selection:$zone){ForEach(["UTC","Asia/Taipei","America/New_York","Europe/London","Asia/Tokyo"],id:\.self){Text($0)}}
                Stepper("開盤分鐘（當日 0 起算）\(open)",value:$open,in:0...1440,step:15);Stepper("收盤分鐘 \(close)",value:$close,in:0...1440,step:15)
                Toggle("週一至週五",isOn:$weekdays);TextField("休市日 YYYY-MM-DD，以逗號分隔",text:$holidays).autocorrectionDisabled();Stepper(days == 0 ? "即時交割（簡化）":"交割 \(days) 個營業日（自訂日曆）",value:$days,in:0...10)
                if model.selected?.asset == .future{DatePicker(model.state?.mode == .offline ? "模擬契約到期時間":"契約到期時間",selection:$expiry)}
            }
            if model.state?.mode == .offline,model.selected?.asset.derivative==true{
                Section("B 自訂自動持有費與結算"){
                    Toggle("按固定模擬時鐘收取持有費",isOn:$scheduledCarry)
                    if scheduledCarry{
                        Stepper("間隔 \(carryHours) 小時（UTC）",value:$carryHours,in:1...168)
                        Stepper("週期偏移 \(carryOffset) 分鐘",value:$carryOffset,in:0...(carryHours*60-1))
                        TextField("多方費率（正扣款、負返還）",text:$longCarry).keyboardType(.numbersAndPunctuation)
                        TextField("空方費率（正扣款、負返還）",text:$shortCarry).keyboardType(.numbersAndPunctuation)
                    }
                    if model.selected?.asset == .future{
                        Toggle("自動每日現金結算",isOn:$dailySettlement)
                        if dailySettlement{Stepper(String(format:"每日結算 %02d:%02d（規則時區）",settlementMinute/60,settlementMinute%60),value:$settlementMinute,in:0...1439,step:15)}
                    }
                    Text("只使用 B 自產標記價與自訂費率；有部位才收費。期貨到期會自動結清並釋放委託。A 不以這些規則冒充真實來源的結算事件。").font(.caption)
                }
            }
            Button("保存未來規則"){Task{guard let i=model.selected,let engine=model.engine,let context=model.context else{return};await model.run{var r=i.rules;r.tick=try Amount(tick);r.quantityStep=try Amount(step);r.multiplier=try Amount(multiplier);r.fees.maker=try Amount(maker);r.fees.taker=try Amount(taker);r.fees.fixed=try Amount(fixed);r.fees.minimum=try Amount(minimum);r.fees.sellTax=try Amount(tax);r.timeZone=zone;r.openMinute=open;r.closeMinute=close;r.weekdaysOnly=weekdays;r.holidays=holidays.split(separator:",").map{String($0).trimmingCharacters(in:.whitespaces)};r.settlementBusinessDays=days;if i.asset == .future{r.expiry=Int64(expiry.timeIntervalSince1970)};if model.state?.mode == .offline,i.asset.derivative{r.carrySchedule=scheduledCarry ? try CarrySchedule(interval:Int64(carryHours*3600),offset:Int64(carryOffset*60),longRate:Amount(longCarry),shortRate:Amount(shortCarry),kind:i.asset == .forex ? "interest":"funding"):nil;r.dailySettlementMinute=i.asset == .future && dailySettlement ? settlementMinute:nil};r.verifiedAt=nil;r.source="使用者自訂模擬規則；非交易所核驗";r.version="custom-\(model.now)";try await engine.updateRules(instrumentID:i.id,rules:r,context:context)}}}
        }.navigationTitle("自訂模擬規則").onAppear{guard let r=model.selected?.rules else{return};tick=r.tick.description;step=r.quantityStep.description;multiplier=r.multiplier.description;maker=r.fees.maker.description;taker=r.fees.taker.description;fixed=r.fees.fixed.description;minimum=r.fees.minimum.description;tax=r.fees.sellTax.description;zone=r.timeZone;open=r.openMinute;close=r.closeMinute;weekdays=r.weekdaysOnly;days=r.settlementBusinessDays ?? 0;holidays=r.holidays.joined(separator:",");if let t=r.expiry{expiry=Date(timeIntervalSince1970:TimeInterval(t))};scheduledCarry=r.carrySchedule != nil;if let p=r.carrySchedule{carryHours=max(1,Int(p.interval/3600));carryOffset=Int(p.offset/60);longCarry=p.longRate.description;shortCarry=p.shortRate.description};dailySettlement=r.dailySettlementMinute != nil;settlementMinute=r.dailySettlementMinute ?? 0}
    }
}
