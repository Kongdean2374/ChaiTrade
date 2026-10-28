import SwiftUI
import ChaiTradeCore

struct ContractAccessView:View{
    @EnvironmentObject var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var understood=false
    @State private var saving=false
    @State private var issue:String?
    var body:some View{Form{
        Section("先了解合約模擬"){
            Text("合約與現貨不同：可開多、開空，並使用槓桿及保證金。價格、資金費與費用可能造成強平或穿倉；負債不會自動歸零。").font(.body)
            Text("所有資金與委託都在本機模擬，不會連到交易所下單。啟用只影響目前帳戶；既有部位即使關閉合約功能仍可平倉。").font(.subheadline).foregroundStyle(.secondary)
            Toggle("我已了解上述風險",isOn:$understood).accessibilityIdentifier("acknowledgeContractRisk")
        }
        if let issue{Text(issue).foregroundStyle(.orange)}
        Button(saving ? "保存中…":"啟用本機合約功能"){enable()}.disabled(!understood || saving || model.interactionBlocked).accessibilityIdentifier("confirmContractAccess")
    }.disabled(saving).navigationTitle("合約模擬風險").navigationBarTitleDisplayMode(.inline).toolbar{Button("取消"){understood=false;dismiss()}.disabled(saving)}.interactiveDismissDisabled(saving)}
    private func enable(){
        guard understood,!saving,let engine=model.engine,let context=model.context else{return};saving=true
        Task{defer{saving=false};do{
            try await engine.updatePreferences(leverageEnabled:true,context:context)
            guard model.context==context else{return};await model.refresh();dismiss()
        }catch{if model.context==context{issue=error.localizedDescription}}}
    }
}

struct ContractPositionRiskView:View{
    @EnvironmentObject var model:AppModel
    let position:Position
    @State private var risk:PositionRiskSnapshot?
    @State private var estimate:LiquidationEstimate?
    @State private var issue:String?
    private var revision:String{"\(position.id)|\(position.quantity)|\(position.average)|\(position.margin)|\(model.state?.quotes[position.instrumentKey]?.sequence ?? 0)|\(model.state?.sequence ?? 0)"}
    var body:some View{VStack(alignment:.leading,spacing:10){
        Text((position.side?.label ?? "合約持倉")+" · "+(position.marginMode == .isolated ? "逐倉":"全倉")).font(.subheadline.bold())
        if let risk{
            LabeledContent("風險狀態",value:risk.level)
            LabeledContent("保證金權益（\(risk.currency)）",value:MarketText.number(risk.equity))
            LabeledContent("維持保證金與平倉費",value:MarketText.number(risk.maintenanceAndClosingFee))
            LabeledContent("風險比率",value:risk.ratio.flatMap{try? ($0*Amount(100)).rounded(2).description}.map{$0+"%"} ?? "權益不足")
        }
        if let estimate{
            if let lower=estimate.lower{LabeledContent("下行估計強平價",value:MarketText.number(lower))}
            if let upper=estimate.upper{LabeledContent("上行估計強平價",value:MarketText.number(upper))}
            if estimate.lower==nil && estimate.upper==nil{Text("此價格範圍未找到強平邊界，仍可能因費用或其他商品變動而改變。").font(.caption)}
            Text(estimate.assumptions).font(.caption).foregroundStyle(.secondary)
        }
        if let issue{Text(issue).font(.caption).foregroundStyle(.orange)}
    }.task(id:revision){await calculate()}}
    private func calculate()async{
        guard let state=model.state,let context=model.context else{return}
        let key=position.id,time=model.now
        do{let result=try await Task.detached(priority:.utility){(try ContractRisk.evaluate(state,positionKey:key,now:time),try ContractRisk.liquidationEstimate(state,positionKey:key,now:time))}.value
            guard !Task.isCancelled,model.context==context else{return};risk=result.0;estimate=result.1;issue=nil
        }catch{guard !Task.isCancelled,model.context==context else{return};risk=nil;estimate=nil;issue="風險價格不完整或已過期，暫時無法提供可靠估計。"}
    }
}
private struct RiskTierDraft:Identifiable{
    let id=UUID()
    var ceiling=""
    var initial="0.05"
    var maintenance="0.005"
    var leverage=20
}
struct ContractRiskRulesView:View{
    @EnvironmentObject var model:AppModel
    @State private var tiers:[RiskTierDraft]=[]
    @State private var haircut="1"
    @State private var saving=false
    var body:some View{Form{
        Section{Text("本機自訂風險規則，並非交易所現行保證金公告。級距按名目金額遞增，最後一階上限留空；維持保證金按各段累加。存在持倉或委託時不可直接改寫。").font(.footnote).foregroundStyle(.orange)}
        ForEach($tiers){$tier in Section("風險級距"){
            TextField("名目金額上限（最後一階留空）",text:$tier.ceiling).keyboardType(.decimalPad)
            TextField("初始保證金率（0.05＝5%）",text:$tier.initial).keyboardType(.decimalPad)
            TextField("維持保證金率",text:$tier.maintenance).keyboardType(.decimalPad)
            Stepper("此級距最高\(tier.leverage)×",value:$tier.leverage,in:1...(model.selected?.rules.maxLeverage ?? 20))
        }}
        Section{Button("增加級距"){tiers.append(RiskTierDraft())}.disabled(tiers.count>=20);if !tiers.isEmpty{Button("移除最後級距",role:.destructive){tiers.removeLast()}}}
        Section("同結算幣抵押品"){
            TextField("抵押計算比例（1＝100%）",text:$haircut).keyboardType(.decimalPad)
            Text("只計入相同帳戶、相同結算幣別。未設定跨幣抵押與轉換規則的資產不會自動共用。").font(.caption)
        }
        Button(saving ? "保存中…":"保存未來風險規則"){Task{await save()}}.disabled(saving || model.interactionBlocked)
    }.navigationTitle("階梯保證金").scrollDismissesKeyboard(.interactively).onAppear{load()}}
    private func load(){guard let rules=model.selected?.rules else{return};haircut=(rules.collateralFactor ?? .one).description;tiers=(rules.riskTiers ?? []).map{tier in var draft=RiskTierDraft();draft.ceiling=tier.upperNotional?.description ?? "";draft.initial=tier.initialRate.description;draft.maintenance=tier.maintenanceRate.description;draft.leverage=tier.maxLeverage;return draft}}
    private func save()async{
        guard !saving,let instrument=model.selected,let engine=model.engine,let context=model.context else{return};saving=true;defer{saving=false}
        _ = await model.run{var rules=instrument.rules;rules.riskTiers=try tiers.map{RiskTier(upperNotional:$0.ceiling.isEmpty ? nil:try Amount($0.ceiling),initialRate:try Amount($0.initial),maintenanceRate:try Amount($0.maintenance),maxLeverage:$0.leverage)};rules.collateralFactor=try Amount(haircut);try rules.validateRiskTiers();rules.source="使用者自訂階梯保證金與抵押規則";rules.version="risk-custom-\(model.now)";try await engine.updateRules(instrumentID:instrument.id,rules:rules,context:context);model.notice="已保存未來風險規則"}
    }
}

struct ProposedContractRiskView:View{
    @EnvironmentObject var model:AppModel
    let request:OrderRequest?
    let price:Amount?
    @State private var result:PositionRiskSnapshot?
    @State private var estimate:LiquidationEstimate?
    @State private var issue:String?
    private var revision:String{guard let request else{return "empty"};return "\(request.instrumentID)|\(request.side)|\(request.positionSide?.rawValue ?? "")|\(request.quantity)|\(price?.description ?? "")|\(request.leverage)|\(request.marginMode)|\(request.reduceOnly)|\(model.state?.sequence ?? 0)"}
    var body:some View{VStack(alignment:.leading,spacing:8){
        if let result{LabeledContent("假設成交後保證金權益",value:MarketText.number(result.equity));LabeledContent("假設成交後風險",value:result.level)}
        if let estimate{if let lower=estimate.lower{LabeledContent("預估下行強平價",value:MarketText.number(lower))};if let upper=estimate.upper{LabeledContent("預估上行強平價",value:MarketText.number(upper))};Text("依所填委託價假設成交；實際成交、費用與後續市場會改變此估計。").font(.caption).foregroundStyle(.secondary)}
        if let issue{Text(issue).font(.caption).foregroundStyle(.orange)}
    }.task(id:revision){await calculate()}}
    private func calculate()async{
        guard let state=model.state,let context=model.context,let request,let price else{result=nil;estimate=nil;return}
        do{try await Task.sleep(for:.milliseconds(250));let time=model.now;let value=try await Task.detached(priority:.utility){try ContractRisk.projected(state,request:request,price:price,now:time)}.value
            guard !Task.isCancelled,model.context==context else{return};result=value?.0;estimate=value?.1;issue=nil
        }catch is CancellationError{}catch{guard !Task.isCancelled,model.context==context else{return};result=nil;estimate=nil;issue="目前資料不足以預估成交後強平邊界；請核對持倉方向、價格與數量。"}
    }
}
