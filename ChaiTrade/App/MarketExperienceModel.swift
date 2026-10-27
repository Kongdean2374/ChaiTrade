import SwiftUI
import ChaiTradeCore

private enum QuoteResult:Sendable {
    case value(QuoteLease,Instrument,Quote)
    case failure(QuoteLease,Instrument,MarketDataFailure)
}
extension AppModel {
    var currentBrowsing:MarketBrowsingState{browsing[market] ?? MarketBrowsingState()}
    var visibleQuoteIDs:Set<String>{visibleOwners.values.reduce(into:Set<String>()){$0.formUnion($1)}}
    var protectedQuoteIDs:Set<String>{
        guard let state else{return []}
        return state.watchlist.union(state.positions.values.filter{$0.quantity != .zero}.map(\.id)).union(state.orders.values.filter{$0.status.open}.map{$0.request.instrumentID}).union(state.alerts.filter{$0.firedAt==nil}.map(\.instrumentID))
    }
    var requiredQuoteIDs:Set<String>{visibleQuoteIDs.union(protectedQuoteIDs).union(selectedID.isEmpty ? []:[selectedID])}
    func restoreProductBrowsing(){
        guard let state else{return}
        browsing=Dictionary(uniqueKeysWithValues:MarketDomain.allCases.map{($0,state.productPreferences?.markets[$0.rawValue] ?? MarketBrowsingState())})
        market=state.productPreferences?.activeMarket ?? .stocks
        selectedID=browsing[market]?.selectedID.flatMap{id in state.instruments.first{$0.id==id && $0.market==market}}?.id ?? defaultProduct(in:market)?.id ?? ""
    }
    func defaultProduct(in market:MarketDomain)->Instrument?{
        let pool=(state?.instruments ?? []).filter{$0.market==market && $0.asset != .index && $0.identity?.legacy != true}
        let preferred=market == .crypto ? "BTC-USD":market == .stocks ? "2330":"EUR/USD"
        return pool.first{$0.symbol==preferred} ?? pool.first
    }
    func editBrowsing(_ market:MarketDomain,change:(inout MarketBrowsingState)->Void){
        var value=browsing[market] ?? MarketBrowsingState();change(&value);browsing[market]=value;browsingDirty.insert(market)
        browseSaveTask?.cancel()
        browseSaveTask=Task{
            do{try await Task.sleep(for:.milliseconds(400))}catch{return}
            guard let engine,let context else{return}
            let pending=browsingDirty;browsingDirty=[]
            for domain in pending.sorted(by:{$0.rawValue<$1.rawValue}){
                guard let value=browsing[domain],self.context==context else{return}
                do{try await engine.saveMarketBrowsing(value,market:domain,activate:domain==self.market,context:context)}catch{self.notice="瀏覽偏好尚未保存，請重試"}
            }
        }
    }
    func switchMarket(_ target:MarketDomain){
        guard target != market else{return}
        market=target;visibleOwners=[:]
        let saved=browsing[target]?.selectedID
        selectedID=state?.instruments.first{$0.id==saved && $0.market==target}?.id ?? defaultProduct(in:target)?.id ?? ""
        chartGeneration=UUID();candleTask?.cancel();candles=[];chartError=nil;chartBefore=nil;chartCount=160
        editBrowsing(target){$0.selectedID=self.selectedID.isEmpty ? nil:self.selectedID}
        restartStream();Task{await ensureQuoteService();if tab==2{await loadChart()}}
    }
    func selectProduct(_ instrument:Instrument){
        if market != instrument.market{switchMarket(instrument.market)}
        selectedID=instrument.id;chartGeneration=UUID();candleTask?.cancel();candles=[];chartError=nil;chartBefore=nil;chartCount=160;tab=2
        editBrowsing(instrument.market){value in value.selectedID=instrument.id;value.recent.removeAll{$0==instrument.id};value.recent.insert(instrument.id,at:0);value.recent=Array(value.recent.prefix(30))}
        restartStream();Task{await quoteScheduler.retry([instrument.id]);await ensureQuoteService();await loadChart()}
    }
    func visible(_ id:String,owner:String,present:Bool){
        if present{visibleOwners[owner,default:[]].insert(id)}else{visibleOwners[owner]?.remove(id)}
        Task{await ensureQuoteService()}
    }
    func removeVisibleOwner(_ owner:String){visibleOwners.removeValue(forKey:owner);Task{await ensureQuoteService()}}
    func loadCredentialReadiness(){
        guard context?.mode == .online else{credentialReady=[:];return}
        for provider in ProviderID.allCases{credentialReady[provider] = !provider.needsKey || ((try? KeychainVault.read(provider.rawValue+".key").isEmpty)==false)}
    }
    func status(for instrument:Instrument)->MarketIssueKind{
        if instrument.halted{return .halted}
        if state?.mode == .offline{if state?.quotes[instrument.id]?.valid==false{return .halted};return instrument.rules.isOpen(at:now) ? .ready:.closed}
        guard let provider=instrument.provider else{return .unsupported}
        if provider.needsKey && credentialReady[provider] != true{return .missingKey}
        guard let quote=state?.quotes[instrument.id] else{return quoteIssues[instrument.id] ?? .loading}
        if quote.quality == .delayed{return .delayed}
        if !instrument.rules.isOpen(at:marketClock){return .closed}
        if !quote.valid || quote.quality != .realtime || marketClock-quote.time>quote.maximumAge{return quoteIssues[instrument.id] == .rateLimited ? .rateLimited:.stale}
        if quote.grade == .E3{return .referenceOnly}
        return .ready
    }
    func canTrade(_ instrument:Instrument)->Bool{
        guard !interactionBlocked,instrument.asset != .index,!instrument.halted,instrument.requiresRuleConfirmation != true,let quote=state?.quotes[instrument.id],quote.valid,instrument.rules.isOpen(at:now) else{return false}
        guard quote.quality == .realtime,now>=quote.time-5,now-quote.time<=quote.maximumAge,now-quote.receivedAt<=quote.maximumAge else{return false}
        guard quote.grade == .E1 || quote.grade == .E2 || (quote.grade == .E3 && state?.allowEstimatedExecution==true) else{return false}
        return !instrument.asset.derivative || (quote.mark ?? .zero) > .zero
    }
    func summary(for instrument:Instrument)->QuoteSummary?{state?.mode == .offline ? simulatedSummaries[instrument.id] ?? state?.quotes[instrument.id]?.summary:state?.quotes[instrument.id]?.summary}
    func updateSimulatedSummaries()async{
        guard let state,let sim=state.simulation,let captured=context else{return}
        let minute=sim.time/60,ids=requiredQuoteIDs
        let needed=state.instruments.filter{ids.contains($0.id) && (summaryMinute != minute || simulatedSummaries[$0.id]==nil)}
        guard !needed.isEmpty else{return}
        summaryTask?.cancel();summaryMinute=minute
        summaryTask=Task{
            let values=await Task.detached(priority:.utility){()->[String:QuoteSummary] in var values:[String:QuoteSummary]=[:];for i in needed{if Task.isCancelled{break};values[i.id]=try? Simulation.summary(i,state:sim)};return values}.value
            guard self.context==captured,!Task.isCancelled else{return}
            for (id,value) in values{simulatedSummaries[id]=value}
        }
    }
    func ensureQuoteService()async{
        guard let context else{return}
        if context.mode == .offline{await updateSimulatedSummaries();return}
        await quoteScheduler.demand(context:context,visible:visibleQuoteIDs,selected:selectedID,protected:protectedQuoteIDs)
        guard foreground,quoteServiceTask==nil else{return}
        let generation=UUID();quoteServiceGeneration=generation
        quoteServiceTask=Task{await quoteLoop(context:context,generation:generation)}
    }
    private func quoteLoop(context:AccountContext,generation:UUID)async{
        defer{if quoteServiceGeneration==generation{fetching=false;quoteServiceTask=nil}}
        while !Task.isCancelled,foreground,self.context==context,state?.mode == .online{
            await quoteScheduler.demand(context:context,visible:visibleQuoteIDs,selected:selectedID,protected:protectedQuoteIDs)
            let leases=await quoteScheduler.next(context:context,now:Int64(Date().timeIntervalSince1970),limit:3)
            if leases.isEmpty{do{try await Task.sleep(for:.milliseconds(500))}catch{return};continue}
            var work:[(QuoteLease,Instrument,MarketDataProvider)]=[]
            for lease in leases{
                guard let instrument=state?.instruments.first(where:{$0.id==lease.instrumentID}),let source=instrument.provider else{_ = await quoteScheduler.complete(lease,now:now,failure:MarketDataFailure(.unsupported));quoteIssues[lease.instrumentID] = .unsupported;continue}
                do{work.append((lease,instrument,try provider(source)));if state?.quotes[instrument.id]==nil{quoteIssues[instrument.id] = .loading}}
                catch{let failure=(error as? MarketDataFailure) ?? MarketDataFailure(.missingKey);_ = await quoteScheduler.complete(lease,now:now,failure:failure);quoteIssues[instrument.id]=failure.kind}
            }
            fetching=true
            let results=await withTaskGroup(of:QuoteResult.self){group in
                for (lease,instrument,service) in work{group.addTask{do{return .value(lease,instrument,try await service.quote(instrument,now:Int64(Date().timeIntervalSince1970),includeSummary:true))}catch{return .failure(lease,instrument,(error as? MarketDataFailure) ?? MarketDataFailure(.connectionFailed))}}}
                var results:[QuoteResult]=[];for await result in group{results.append(result)};return results
            }
            guard !Task.isCancelled,self.context==context,foreground,let engine else{return}
            var updated:Set<String>=[]
            for result in results{
                switch result{
                case .value(let lease,let instrument,let quote):
                    guard await quoteScheduler.complete(lease,now:now) else{continue}
                    do{try await engine.ingest(quote,now:now,context:context);quoteIssues[instrument.id] = quote.quality == .realtime ? .ready:quote.quality == .delayed ? .delayed:.stale;updated.insert(instrument.id)}catch{quoteIssues[instrument.id] = .connectionFailed}
                case .failure(let lease,let instrument,let failure):
                    guard await quoteScheduler.complete(lease,now:now,failure:failure) else{continue}
                    quoteIssues[instrument.id]=failure.kind;quoteRetryAt[instrument.id]=now+(failure.retryAfter ?? 15)
                    try? await engine.markMonitoringGap(instrumentID:instrument.id,time:now,context:context)
                }
            }
            await refresh();fetching=false
            if tab==2,updated.contains(selectedID),now-lastChartRefresh>=10,!chartLoading{lastChartRefresh=now;Task{await self.loadChart()}}
        }
    }
    func loadNews(force:Bool=false)async{
        guard let state,let context,!newsLoading else{return}
        if let simulation=state.simulation{marketNews=SimulationNews.stories(state:simulation);newsIssue=nil;return}
        guard force || now-lastNewsFetch>120 || marketNews.isEmpty else{return}
        newsLoading=true;defer{newsLoading=false};lastNewsFetch=now
        var stories:[MarketNewsStory]=[],issues:[String]=[]
        do{stories=try await PublicNewsFeed.fetch(mode:.online,transport:ReadOnlyTransport(mode:.online),now:now)}catch{issues.append("官方總體新聞目前無法載入，請稍後重試。")}
        if credentialReady[.alpaca]==true{
            let symbols=state.instruments.filter{$0.provider == .alpaca && state.watchlist.contains($0.id)}.map(\.symbol)
            do{stories += try await provider(.alpaca).news(symbols:symbols,now:now)}catch{issues.append("自選公司新聞需對應來源授權；可繼續查看官方總體新聞。")}
        }
        guard self.context==context,!Task.isCancelled else{return}
        marketNews=Dictionary(stories.map{($0.id,$0)},uniquingKeysWith:{_,new in new}).values.sorted{$0.publishedAt>$1.publishedAt};newsIssue=issues.isEmpty ? nil:issues.joined(separator:"\n")
    }
    func refreshCatalog(_ providerID:ProviderID)async{
        guard context?.mode == .online,!catalogLoading,let engine,let context else{return}
        catalogLoading=true;defer{catalogLoading=false}
        do{let products=try await provider(providerID).products();guard self.context==context else{return};try await engine.importOnlineInstruments(products,context:context);await refresh();catalogIssue="已更新 \(products.count) 個商品；既有部位與歷史保留。"}catch{catalogIssue=error.localizedDescription}
    }
}
