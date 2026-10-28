import SwiftUI
import UIKit
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
        return state.watchlist.union(state.positions.values.filter{$0.quantity != .zero}.map(\.instrumentKey)).union(state.orders.values.filter{$0.status.open}.map{$0.request.instrumentID}).union(state.alerts.filter{$0.firedAt==nil}.map(\.instrumentID))
    }
    var selectedQuoteID:String{selected?.quoteKey(board:selected?.usesTaiwanBoards==true ? selectedBoard:nil) ?? selectedID}
    var requiredQuoteIDs:Set<String>{visibleQuoteIDs.union(protectedQuoteIDs).union(selectedID.isEmpty ? []:[selectedID,selectedQuoteID])}
    func restoreProductBrowsing(){
        guard let state else{return}
        latestOrderReceipt=nil
        browsing=Dictionary(uniqueKeysWithValues:MarketDomain.allCases.map{($0,state.productPreferences?.markets[$0.rawValue] ?? MarketBrowsingState())})
        marketNews=[];newsIssue=nil;lastNewsFetch=0;simulatedSummaries=[:];summaryMinute = -1
        market=state.productPreferences?.activeMarket ?? .stocks
        selectedID=browsing[market]?.selectedID.flatMap{id in state.instruments.first{$0.id==id && $0.market==market}}?.id ?? defaultProduct(in:market)?.id ?? ""
        selectedBoard=selected?.usesTaiwanBoards==true ? .oddLot:.regular
        restoreTradeWorkspace()
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
            await flushBrowsing()
        }
    }
    func flushBrowsing()async{
        guard let engine,let context else{return}
        let pending=browsingDirty;browsingDirty=[]
        for domain in pending.sorted(by:{$0.rawValue<$1.rawValue}){
            guard let value=browsing[domain],self.context==context else{return}
            do{try await engine.saveMarketBrowsing(value,market:domain,activate:domain==self.market,context:context)}catch{browsingDirty.insert(domain);self.notice="瀏覽偏好尚未保存，請重試"}
        }
    }

    func switchMarket(_ target:MarketDomain){
        #if DEBUG
        if UITestSupport.session != nil{uiTestMarketRequests.append(target.rawValue)}
        #endif
        guard target != market else{return}
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        market=target;visibleOwners=[:]
        quoteServiceTask?.cancel();quoteServiceTask=nil;quoteServiceGeneration=UUID();boardQuoteTask?.cancel()
        let saved=browsing[target]?.selectedID
        selectedID=state?.instruments.first{$0.id==saved && $0.market==target}?.id ?? defaultProduct(in:target)?.id ?? ""
        chartGeneration=UUID();candleTask?.cancel();candles=[];chartError=nil;chartBefore=nil;chartCount=160
        editBrowsing(target){$0.selectedID=self.selectedID.isEmpty ? nil:self.selectedID}
        selectedBoard=selected?.usesTaiwanBoards==true ? .oddLot:.regular
        restartStream();Task{if let context{await quoteScheduler.cancel(context:context)};await ensureQuoteService();await requestSelectedBoard();if tab==2{await loadChart()}}
    }
    func selectProduct(_ instrument:Instrument){browseProduct(instrument)}
    func focusProduct(_ instrument:Instrument){
        #if DEBUG
        if UITestSupport.session != nil{uiTestProductSelections.append(instrument.id)}
        #endif
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
        guard selectedID != instrument.id else{return}
        quoteServiceTask?.cancel();quoteServiceTask=nil;quoteServiceGeneration=UUID();boardQuoteTask?.cancel()
        selectedID=instrument.id;chartGeneration=UUID();candleTask?.cancel();candles=[];chartError=nil;chartBefore=nil;chartCount=160
        selectedBoard=instrument.usesTaiwanBoards ? .oddLot:.regular
        restartStream();Task{if let context{await quoteScheduler.cancel(context:context)};await requestSelectedBoard();await quoteScheduler.retry([instrument.id]);await ensureQuoteService();await loadChart()}
    }
    func visible(_ id:String,owner:String,present:Bool){
        if present{guard state?.instruments.contains(where:{$0.id==id})==true else{return};visibleOwners[owner,default:[]].insert(id)}else{visibleOwners[owner]?.remove(id)}
        Task{await ensureQuoteService()}
    }
    func removeVisibleOwner(_ owner:String){visibleOwners.removeValue(forKey:owner);Task{await ensureQuoteService()}}
    func changeBoard(_ board:TradingBoard){selectedBoard=board;clearChartCaches();candles=[];Task{await requestSelectedBoard();await loadChart()}}
    func requestSelectedBoard()async{
        guard context?.mode == .online else{return}
        // Regular and odd-lot books share leases, cooldowns and in-flight coalescing.
        await ensureQuoteService()
    }
    func loadCredentialReadiness(){
        guard context?.mode == .online else{credentialReady=[:];return}
        for provider in ProviderID.allCases{credentialReady[provider] = !provider.needsKey || ((try? KeychainVault.read(provider.rawValue+".key").isEmpty)==false)}
    }
    func status(for instrument:Instrument,board:TradingBoard?=nil)->MarketIssueKind{
        let key=instrument.quoteKey(board:board)
        if instrument.halted{return .halted}
        if state?.mode == .offline{if state?.quotes[key]?.valid==false{return .halted};return instrument.rules.isOpen(at:now) ? .ready:.closed}
        guard let provider=instrument.provider else{return .unsupported}
        if provider.needsKey && credentialReady[provider] != true{return .missingKey}
        guard let quote=state?.quotes[key] else{return quoteIssues[key] ?? .loading}
        if let issue=quoteIssues[key],![MarketIssueKind.ready,.loading,.stale].contains(issue),!quote.valid{return issue}
        if let issue=quote.sourceIssue{return issue}
        if quote.quality == .delayed{return .delayed}
        if !instrument.boardIsOpen(board,at:marketClock){return .closed}
        if !quote.valid || quote.quality != .realtime || marketClock-quote.time>quote.maximumAge || marketClock-quote.receivedAt>quote.maximumAge || marketClock<quote.time-5{return quoteIssues[key].flatMap{[MarketIssueKind.ready,.loading].contains($0) ? nil:$0} ?? .stale}
        if quote.grade == .E3{return .referenceOnly}
        if quote.bids.isEmpty || quote.asks.isEmpty{return .referenceOnly}
        if instrument.requiresRuleConfirmation==true{return .rulesUnverified}
        if instrument.asset.derivative && (quote.mark ?? .zero) <= .zero{return .missingRiskPrice}
        return .ready
    }
    func canTrade(_ instrument:Instrument,board:TradingBoard?=nil)->Bool{
        let board=instrument.usesTaiwanBoards ? (board ?? selectedBoard):nil
        guard !interactionBlocked,instrument.asset != .index,!instrument.halted,instrument.requiresRuleConfirmation != true,let quote=state?.quotes[instrument.quoteKey(board:board)],quote.valid,(quote.sourceIssue == nil || quote.sourceIssue == .ready),instrument.boardIsOpen(board,at:now) else{return false}
        guard quote.quality == .realtime,now>=quote.time-5,now-quote.time<=quote.maximumAge,now-quote.receivedAt<=quote.maximumAge else{return false}
        guard quote.bids.contains(where:{$0.price > .zero && $0.quantity > .zero}),quote.asks.contains(where:{$0.price > .zero && $0.quantity > .zero}),let bid=quote.bids.first,let ask=quote.asks.first,bid.price > .zero,bid.price<ask.price else{return false}
        guard quote.grade == .E1 || quote.grade == .E2 || (state?.mode == .offline && quote.grade == .E3 && state?.allowEstimatedExecution==true) else{return false}
        return !instrument.asset.derivative || (quote.mark ?? .zero) > .zero
    }
    func summary(for instrument:Instrument)->QuoteSummary?{state?.mode == .offline ? simulatedSummaries[instrument.id] ?? state?.quotes[instrument.id]?.summary:state?.quotes[instrument.id]?.summary}
    func updateSimulatedSummaries()async{
        guard let state,let sim=state.simulation,let captured=context,let engine else{return}
        let minute=sim.time/60,ids=requiredQuoteIDs
        if summaryMinute != minute{summaryTask?.cancel();summaryTask=nil;summaryAttemptedIDs=[];summaryMinute=minute;summaryGeneration=UUID()}
        guard summaryTask==nil else{return}
        let needed=state.instruments.filter{ids.contains($0.id) && !summaryAttemptedIDs.contains($0.id)}
        guard !needed.isEmpty else{return}
        summaryAttemptedIDs.formUnion(needed.map(\.id));let generation=UUID();summaryGeneration=generation
        summaryTask=Task{
            let worker=Task.detached(priority:.utility){()->[String:QuoteSummary] in var values:[String:QuoteSummary]=[:];for i in needed{if Task.isCancelled{break};if let start=try? Simulation.summaryHistoryStart(i,state:sim),let history=try? await engine.simulationSnapshot(instrumentID:i.id,from:start,context:captured){values[i.id]=try? Simulation.summary(i,state:history)}};return values}
            let values=await withTaskCancellationHandler{await worker.value}onCancel:{worker.cancel()}
            guard summaryGeneration==generation else{return};summaryTask=nil
            guard self.context==captured,!Task.isCancelled,let currentTime=self.state?.simulation?.time,currentTime/60==minute else{return}
            for (id,value) in values{simulatedSummaries[id]=value}
            await updateSimulatedSummaries()
        }
    }
    func ensureQuoteService()async{
        guard let context else{return}
        if context.mode == .offline{if let engine{do{try await engine.setSimulationDemand(selectedID.isEmpty ? []:[selectedID],context:context);guard self.context==context else{return};state=await engine.snapshot()}catch{self.notice=error.localizedDescription}};await updateSimulatedSummaries();return}
        await quoteScheduler.demand(context:context,visible:visibleQuoteIDs.union(selectedID.isEmpty ? []:[selectedID]),selected:selectedQuoteID,protected:protectedQuoteIDs)
        guard foreground,quoteServiceTask==nil else{return}
        let generation=UUID();quoteServiceGeneration=generation
        quoteServiceTask=Task{await quoteLoop(context:context,generation:generation)}
    }
    private func quoteLoop(context:AccountContext,generation:UUID)async{
        defer{if quoteServiceGeneration==generation{fetching=false;quoteServiceTask=nil}}
        while !Task.isCancelled,foreground,self.context==context,state?.mode == .online{
            await quoteScheduler.demand(context:context,visible:visibleQuoteIDs.union(selectedID.isEmpty ? []:[selectedID]),selected:selectedQuoteID,protected:protectedQuoteIDs)
            let leases=await quoteScheduler.next(context:context,now:Int64(Date().timeIntervalSince1970),limit:3)
            if leases.isEmpty{do{try await Task.sleep(for:.milliseconds(500))}catch{return};continue}
            var work:[(QuoteLease,Instrument,MarketDataProvider,TradingBoard?)]=[]
            for lease in leases{
                guard let instrument=state?.instruments.first(where:{$0.id==lease.instrumentID || ($0.usesTaiwanBoards && $0.quoteKey(board:.oddLot)==lease.instrumentID)}),let source=instrument.provider else{_ = await quoteScheduler.complete(lease,now:now,failure:MarketDataFailure(.unsupported));quoteIssues[lease.instrumentID] = .unsupported;continue}
                do{let board:TradingBoard?=instrument.id==lease.instrumentID ? nil:.oddLot;work.append((lease,instrument,try provider(source),board));if state?.quotes[lease.instrumentID]==nil{quoteIssues[lease.instrumentID] = .loading}}
                catch{let failure=(error as? MarketDataFailure) ?? MarketDataFailure(.missingKey);_ = await quoteScheduler.complete(lease,now:now,failure:failure);quoteIssues[lease.instrumentID]=failure.kind}
            }
            fetching=true
            let results=await withTaskGroup(of:QuoteResult.self){group in
                for (lease,instrument,service,board) in work{group.addTask{do{return .value(lease,instrument,try await service.quote(instrument,now:Int64(Date().timeIntervalSince1970),includeSummary:true,board:board))}catch{return .failure(lease,instrument,(error as? MarketDataFailure) ?? MarketDataFailure(.connectionFailed))}}}
                var results:[QuoteResult]=[];for await result in group{results.append(result)};return results
            }
            guard !Task.isCancelled,self.context==context,foreground,let engine else{return}
            var updated:Set<String>=[]
            for result in results{
                switch result{
                case .value(let lease,let instrument,let quote):
                    guard await quoteScheduler.complete(lease,now:now) else{continue}
                    do{try await engine.ingest(quote,now:now,context:context);quoteIssues[lease.instrumentID] = quote.quality == .realtime ? .ready:quote.quality == .delayed ? .delayed:.stale;updated.insert(instrument.id)}catch{quoteIssues[lease.instrumentID] = .connectionFailed}
                case .failure(let lease,let instrument,let failure):
                    guard await quoteScheduler.complete(lease,now:now,failure:failure) else{continue}
                    quoteIssues[lease.instrumentID]=failure.kind;quoteRetryAt[lease.instrumentID]=now+(failure.retryAfter ?? 15)
                    try? await engine.markMonitoringGap(instrumentID:lease.instrumentID,time:now,context:context)
                }
            }
            await refresh();fetching=false
            if (tab==2 || (tab==1 && !(marketPaths[market] ?? []).isEmpty)),updated.contains(selectedID),now-lastChartRefresh>=10,!chartLoading{
                await requestSelectedBoard();lastChartRefresh=now;Task{await self.loadChart()}}
        }
    }
    func loadNews(force:Bool=false)async{
        guard let state,let context,!newsLoading else{return}
        if let simulation=state.simulation{marketNews=SimulationNews.stories(state:simulation);newsIssue=nil;return}
        guard state.mode == .online else{return}
        guard lastNewsFetch==0 || now-lastNewsFetch >= (force ? 15:900) else{return}
        newsLoading=true;defer{newsLoading=false};lastNewsFetch=now
        var stories:[MarketNewsStory]=[],issues:[String]=[]
        do{
            let results=try await PublicNewsFeed.fetchAll(mode:.online,transport:ReadOnlyTransport(mode:.online),now:now,instruments:state.instruments)
            guard self.context==context,!Task.isCancelled else{return}
            for result in results{stories+=result.stories;if let issue=result.issue{issues.append(result.source.label+"："+issue)}}
        }catch is CancellationError{return}catch{issues.append("新聞來源目前無法載入，請稍後重試。")}
        if credentialReady[.alpaca]==true{
            let symbols=state.instruments.filter{$0.provider == .alpaca && state.watchlist.contains($0.id)}.map(\.symbol)
            do{stories += try await provider(.alpaca).news(symbols:symbols,now:now)}catch{issues.append("自選公司新聞需對應來源授權；可繼續查看官方總體新聞。")}
        }
        guard self.context==context,!Task.isCancelled else{return}
        marketNews=Dictionary(stories.map{($0.id,$0)},uniquingKeysWith:{_,new in new}).values.sorted{$0.publishedAt>$1.publishedAt};newsIssue=issues.isEmpty ? nil:issues.joined(separator:"\n")
    }
    @discardableResult func showCatalogInstrument(_ id:String,expectedContext:AccountContext)->Bool{
        guard context==expectedContext,expectedContext.mode == .online,let instrument=state?.instruments.first(where:{$0.id==id}) else{return false}
        catalogVisible=false;select(instrument);catalogNavigationRevision=UUID();return true
    }
    func refreshCatalog(_ providerID:ProviderID)async{
        guard context?.mode == .online,!catalogLoading,let engine,let context else{return}
        catalogLoading=true;defer{catalogLoading=false}
        do{let products=try await provider(providerID).products();guard self.context==context else{return};try await engine.importOnlineInstruments(products,context:context);await refresh();catalogIssue="已更新 \(products.count) 個商品；既有部位與歷史保留。"}catch{catalogIssue=error.localizedDescription}
    }
}
