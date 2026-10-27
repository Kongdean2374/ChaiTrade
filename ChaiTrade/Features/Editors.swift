import SwiftUI
import UIKit
import ChaiTradeCore

struct CustomInstrumentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var name=""
    @State private var symbol=""
    @State private var asset=AssetClass.crypto
    @State private var currency="TWD"
    @State private var price="100"
    @State private var tick="0.01"
    @State private var step="1"
    @State private var multiplier="1"
    @State private var fee="0.001"
    @State private var volatility=0.002
    @State private var liquidity=1000
    var body: some View {
        Form{
            TextField("商品名稱",text:$name);TextField("唯一代碼（A–Z／0–9）",text:$symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Picker("類別",selection:$asset){ForEach(AssetClass.allCases,id:\.self){Text($0.label)}}
            TextField("報價幣別",text:$currency).textInputAutocapitalization(.characters)
            TextField("初始價",text:$price).keyboardType(.decimalPad);TextField("最小跳動",text:$tick).keyboardType(.decimalPad);TextField("數量級距",text:$step).keyboardType(.decimalPad);TextField("合約乘數",text:$multiplier).keyboardType(.decimalPad);TextField("比例費率",text:$fee).keyboardType(.decimalPad)
            Stepper("流動性單位 \(liquidity)",value:$liquidity,in:10...10000,step:10)
            VStack{Text("波動率 \(volatility,specifier:"%.3f")");Slider(value:$volatility,in:0.001...0.02,step:0.001)}
            Text("此商品採自訂模擬規則與全天時段。已建立後不直接刪除或修改乘數，避免破壞既有持倉。").font(.caption)
            Button("建立離線模擬商品"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{
                guard !name.isEmpty,symbol.range(of:"^[A-Z0-9]{1,20}$",options:.regularExpression) != nil,currency.range(of:"^[A-Z]{3,8}$",options:.regularExpression) != nil else{throw TradeError.invalid("名稱、商品或幣別代碼不合法")}
                var rules=try RulePack(tick:Amount(tick),quantityStep:Amount(step));rules.multiplier=try Amount(multiplier);rules.fees.taker=try Amount(fee);rules.fees.maker=rules.fees.taker
                guard rules.multiplier > .zero,rules.fees.taker >= .zero,rules.fees.taker < .one else{throw TradeError.invalid("乘數或費率不合法")}
                var i=try Instrument(id:"SIM:CUSTOM:\(symbol)",symbol:symbol,name:name,asset:asset,currency:currency,rules:rules,initialPrice:Amount(price));i.liquidity=liquidity;i.volatility=volatility
                try await engine.addInstrument(i,context:context)
            };if model.error == nil{dismiss()}}}
        }.navigationTitle("自訂商品").toolbar{Button("取消"){dismiss()}}
    }
}
struct AlertEditor: View {
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) var dismiss
    @State private var value=""
    @State private var above=true
    @State private var percent=false
    @State private var basis=AlertPriceBasis.creationPrice
    @State private var saving=false
    @State private var instrumentID:String?
    @State private var owner:AccountContext?
    @State private var board:TradingBoard?
    @State private var intentID=UUID().uuidString
    var body:some View{Form{
        Section("建立此商品提醒"){
            Text(model.state?.instruments.first{$0.id==(instrumentID ?? model.selectedID)}?.name ?? "")
            Picker("提醒方式",selection:$percent){Text("到價").tag(false);Text("百分比變化").tag(true)}.pickerStyle(.segmented).accessibilityIdentifier("priceAlertKind")
            TextField(percent ? "變化百分比，例如 5":"提醒價",text:$value).keyboardType(.decimalPad).accessibilityIdentifier("priceAlertValue")
            Toggle(above ? "向上觸發":"向下觸發",isOn:$above)
            if percent{Picker("固定基準",selection:$basis){ForEach(AlertPriceBasis.allCases,id:\.self){Text($0.label)}};Text("基準與觸發價建立後固定，不會跟隨新報價移動；可在下方查看保存值。").font(.caption).foregroundStyle(.secondary)}

        }
        Section("此商品的提醒"){
            let alerts=(model.state?.alerts ?? []).filter{$0.instrumentID==(instrumentID ?? model.selectedID)}
            if alerts.isEmpty{Text("尚未建立提醒").foregroundStyle(.secondary)}
            ForEach(alerts){alert in VStack(alignment:.leading,spacing:6){
                Text("\(alert.above ? "向上":"向下")到價 \(alert.price)")
                if let percent=alert.percentage,let baseline=alert.baseline{Text("\(alert.basis?.label ?? "固定基準") \(baseline) · \(percent)%").font(.caption);if let time=alert.baselineTime{Text(Date(timeIntervalSince1970:TimeInterval(time)).formatted()).font(.caption2)}}
                Text(alert.firedAt.map{"已觸發 · "+Date(timeIntervalSince1970:TimeInterval($0)).formatted()} ?? "監控中").font(.caption).foregroundStyle(.secondary)
                Button("刪除提醒",role:.destructive){Task{guard let engine=model.engine,let context=owner else{return};await model.run{try await engine.removeAlert(id:alert.id,context:context)}}}
            }}
        }
        Text("僅在引擎實際運作時監控；補算發現的事件會保留模擬時間。不保證鎖屏後即時提醒。缺少有效價格時不建立百分比基準。").font(.footnote)
    }.scrollDismissesKeyboard(.immediately).safeAreaInset(edge:.bottom){createButton.padding(.horizontal,16).padding(.vertical,8).background(.bar)}.interactiveDismissDisabled(saving).navigationTitle("價格提醒").toolbar{
        ToolbarItem(placement:.topBarTrailing){Button("完成"){dismiss()}.disabled(saving)}
        ToolbarItemGroup(placement:.keyboard){Spacer();Button("收起鍵盤"){UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}}
    }.onAppear{if instrumentID==nil{instrumentID=model.selectedID;owner=model.context;board=model.selected?.usesTaiwanBoards==true ? model.selectedBoard:nil}}}
    private var createButton:some View{
        Button(saving ? "建立中…":"建立帳戶內提醒"){
                guard !saving,!value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return};saving=true
                let id=intentID,product=instrumentID ?? model.selectedID,context=owner,raw=value,percent=percent,above=above,basis=basis,board=board
                Task{defer{saving=false};guard let engine=model.engine,let context else{return};await model.run{
                    let amount=try Amount(raw)
                    if percent{try await engine.addPercentageAlert(id:id,instrumentID:product,percentage:amount,above:above,basis:basis,board:board,time:model.now,context:context)}
                    else{var alert=PriceAlert(instrumentID:product,price:amount,above:above);alert.id=id;alert.board=board;try await engine.addAlert(alert,context:context)}
                };if model.error==nil{value="";intentID=UUID().uuidString}}
            }.disabled(saving || model.interactionBlocked || owner != model.context || value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).font(.headline).frame(maxWidth:.infinity,minHeight:48).buttonStyle(.borderedProminent).accessibilityIdentifier("createPriceAlert")
    }
}
struct DrawingEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) var dismiss
    @State private var kind="horizontal"
    @State private var p1=""
    @State private var p2=""
    @State private var t1=Date()
    @State private var t2=Date()
    var body: some View {
        Form{
            Picker("工具",selection:$kind){Text("水平線").tag("horizontal");Text("趨勢線").tag("trend");Text("垂直標記").tag("vertical");Text("矩形區域").tag("rectangle");Text("Fibonacci 回撤").tag("fibonacci")}
            TextField("價格一",text:$p1).keyboardType(.decimalPad);TextField("價格二",text:$p2).keyboardType(.decimalPad);DatePicker("時間一",selection:$t1);DatePicker("時間二",selection:$t2)
            Button("保存繪圖"){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{let a=try Amount(p1),b=try Amount(p2.isEmpty ? p1:p2);try await engine.saveDrawing(Drawing(instrumentID:model.selectedID,kind:kind,time1:Int64(t1.timeIntervalSince1970),price1:a.displayDouble,time2:Int64(t2.timeIntervalSince1970),price2:b.displayDouble),context:context)};if model.error == nil{dismiss()}}}
            Section("此帳戶的商品繪圖"){
                ForEach((model.state?.drawings ?? []).filter{$0.instrumentID==model.selectedID}){d in HStack{Text("\(d.kind) · \(d.price1,specifier:"%.4f")");Spacer();Button("刪除",role:.destructive){Task{guard let engine=model.engine,let context=model.context else{return};await model.run{try await engine.removeDrawing(id:d.id,context:context)}}}.buttonStyle(.borderless)}}
            }
        }.navigationTitle("圖表繪圖").toolbar{Button("完成"){dismiss()}}.onAppear{p1=model.quote?.last.description ?? "100";p2=p1;t2=Date(timeIntervalSince1970:TimeInterval(model.now));t1=t2.addingTimeInterval(-3600)}
    }
}
