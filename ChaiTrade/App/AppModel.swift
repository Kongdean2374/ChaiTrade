import SwiftUI
import UIKit
import ChaiTradeCore
import Security
import WebKit
import UniformTypeIdentifiers

enum KeychainVault {
    static func read(_ key: String) throws -> String {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"ChaiTrade.market-data",kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess,let data = result as? Data,let string = String(data:data,encoding:.utf8) else { throw TradeError.unavailable("Keychain 已鎖定或無法存取") }
        return string
    }
    static func write(_ value: String, key: String) throws {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"ChaiTrade.market-data",kSecAttrAccount as String:key]
        if value.isEmpty { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw TradeError.unavailable("無法刪除金鑰") }; return }
        let values: [String:Any] = [kSecValueData as String:Data(value.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary,values as CFDictionary)
        if result == errSecItemNotFound { var add=query;add.merge(values) { _,new in new };guard SecItemAdd(add as CFDictionary,nil) == errSecSuccess else { throw TradeError.unavailable("無法保存行情金鑰") } }
        else if result != errSecSuccess { throw TradeError.unavailable("無法更新行情金鑰") }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data,.json,.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data=data }
    init(configuration: ReadConfiguration) throws { data=configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}
struct ChartAmendment: Identifiable {
    let id=UUID()
    let order: Order
    let price: Amount
}

@MainActor final class AppModel: ObservableObject {
    #if DEBUG
    @Published var uiTestOperations=0
    @Published var uiTestMutationStarts=0
    @Published var uiTestMaxOperations=0
    @Published var uiTestMarketRequests:[String]=[]
    @Published var uiTestProductSelections:[String]=[]
    #endif
    @Published var market=MarketDomain.stocks
    @Published var browsing:[MarketDomain:MarketBrowsingState]=[:]
    @Published var quoteIssues:[String:MarketIssueKind]=[:]
    @Published var quoteRetryAt:[String:Int64]=[:]
    @Published var marketClock=Int64(Date().timeIntervalSince1970)
    @Published var simulatedSummaries:[String:QuoteSummary]=[:]
    @Published var marketNews:[MarketNewsStory]=[]
    @Published var newsLoading=false
    @Published var newsIssue:String?
    @Published var catalogLoading=false
    @Published var catalogIssue:String?
    @Published var credentialReady:[ProviderID:Bool]=[:]
    var visibleOwners:[String:Set<String>]=[:]
    let quoteScheduler=VisibleQuoteScheduler()
    var quoteServiceTask:Task<Void,Never>?
    var quoteServiceGeneration=UUID()
    var browseSaveTask:Task<Void,Never>?
    var browsingDirty:Set<MarketDomain>=[]
    var summaryTask:Task<Void,Never>?
    var summaryMinute:Int64 = -1
    var summaryAttemptedIDs:Set<String>=[]
    var summaryGeneration=UUID()
    var lastNewsFetch:Int64=0
    var lastChartRefresh:Int64=0
    @Published var state: AccountState?
    @Published var settings=AppSettings()
    @Published var error: String?
    @Published var notice: String?
    @Published var loading=false
    @Published var progress: Double?
    @Published var selectedID=""
    @Published var selectedBoard=TradingBoard.regular
    var boardQuoteTask:Task<Void,Never>?
    @Published var tab=0
    @Published var stateRevision=UUID()
    @Published var candles: [Candle]=[]
    @Published var chartError: String?
    @Published var chartLimitation: String?
    @Published var catalogVisible=false
    @Published var catalogNavigationRevision=UUID()
    @Published var journalScreenshot: Data?
    weak var chartWebView:WKWebView?
    @Published var interval: Int64=60
    @Published var chartCount=160
    @Published var chartBefore:Int64?
    @Published var chartLoading=false
    @Published var fetching=false
    @Published var providerStatus: [ProviderID:String]=[:]
    @Published var exportDocument: ExportDocument?
    @Published var exportName="ChaiTrade-backup"
    @Published var exporting=false
    @Published var exportingWork=false
    @Published var maintainingAccount=false
    @Published var fileArchiveWorking=false
    @Published var fileArchiveCanCancel=true
    @Published var fileArchiveProgress=0.0
    @Published var fileArchivePhase=""
    @Published var fileArchiveURL:URL?
    var fileArchiveOperation:Task<Void,Never>?
    var fileArchiveGeneration=UUID()
    @Published var catchupTarget: Int64?
    @Published var clockWarning: String?
    @Published private(set) var catchingUp=false
    @Published var chartAmendment: ChartAmendment?
    @Published var requestedAccountNotice:NoticeLink?
    @Published var openedNotice:NoticeDestination?
    private(set) var engine: TradingEngine?
    private(set) var context: AccountContext?
    private let notifications=LocalNotifications()
    private var notifying=false
    private var booted=false
    private var busy=false
    var foreground=true
    private var lastUptime=ProcessInfo.processInfo.systemUptime
    private var fractionalTime=0.0
    private var lastFetch=0.0
    var chartGeneration=UUID()
    var candleTask:Task<MarketHistoryResult,Error>?
    private var chartCache:[String:[Candle]]=[:]
    private var chartCacheLimitations:[String:String]=[:]
    private var chartCacheOrder:[String]=[]
    private var streamTask: Task<Void,Never>?
    let root: URL
    init() {
        #if DEBUG
        let modelInitStarted=ProcessInfo.processInfo.systemUptime
        defer{if UITestSupport.session != nil{NSLog("CHAI_LAUNCH_PHASE modelInitMilliseconds %.1f",(ProcessInfo.processInfo.systemUptime-modelInitStarted)*1000)}}
        #endif
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        #if DEBUG
        root=UITestSupport.root(base:base)
        do{try UITestSupport.prepare(root:root)}catch{self.error="獨立 UI 測試資料建立失敗：\(error.localizedDescription)"}
        #else
        root=base.appendingPathComponent("ChaiTrade",isDirectory:true)
        #endif
        do { settings=try AppSettings.load(root:root) } catch { self.error="設定檔無法讀取，保留原資料：\(error.localizedDescription)" }
        #if DEBUG
        if UITestSupport.session != nil{
            if ProcessInfo.processInfo.arguments.contains("--uitest-light"){settings.theme="light"}
            if ProcessInfo.processInfo.arguments.contains("--uitest-dark"){settings.theme="dark"}
        }
        #endif
    }
    var now: Int64 { state?.simulation?.time ?? Int64(Date().timeIntervalSince1970) }
    var selected: Instrument? { state?.instruments.first { $0.id == selectedID } }
    var quote: Quote? {guard let selected else{return nil};return state?.quotes[selected.quoteKey(board:selected.usesTaiwanBoards ? selectedBoard:nil)]}
    var valuation: Valuation? { state.flatMap { try? Analytics.valuation($0,now:now) } }
    func money(_ value: Amount?) -> String { settings.hideBalances ? "••••••" : MarketText.number(value) }
    var interactionBlocked:Bool { progress != nil || catchupTarget != nil || maintainingAccount || clockWarning != nil }
    @discardableResult func run(_ operation: () async throws -> Void) async ->Bool {
        guard !interactionBlocked else{error="市場事件尚未處理完成，請完成補算或明確放棄後再操作";return false}
        #if DEBUG
        uiTestOperations+=1;uiTestMutationStarts+=1;uiTestMaxOperations=max(uiTestMaxOperations,uiTestOperations);defer{uiTestOperations-=1}
        await UITestSupport.delay()
        #endif
        guard !interactionBlocked else{error="市場事件處理中，請完成後再操作";return false}
        do { try await operation();await refresh();return true } catch { self.error=error.localizedDescription;return false }
    }
    func boot() async {
        guard !booted,settings.onboarded else { return }
        #if DEBUG
        let accountBootStarted=ProcessInfo.processInfo.systemUptime
        defer{if UITestSupport.session != nil{NSLog("CHAI_LAUNCH_PHASE accountBootMilliseconds %.1f",(ProcessInfo.processInfo.systemUptime-accountBootStarted)*1000)}}
        #endif
        booted=true;loading=true;defer{loading=false}
        do {
            let target=settings.pendingMode ?? settings.activeMode
            let switched=target != settings.activeMode
            let ctx=AccountContext(mode:target),root=self.root
            let (existing,service)=try await Task.detached{let repo=try AccountRepository(root:root,mode:target);guard let existing=try repo.load() else{throw TradeError.corrupt("帳戶不存在，請使用備份恢復；不會重建空帳戶覆蓋資料")};let service=try TradingEngine(context:ctx,repository:repo,initial:existing,wallClock:{Int64(Date().timeIntervalSince1970)});return (existing,service)}.value
            try await service.prepareProductExperience(context:ctx)
            let initialBooks=Set((existing.productPreferences?.markets.values.compactMap(\.selectedID) ?? [])+(existing.instruments.first.map{[$0.id]} ?? []))
            try await service.initializeQuotes(fullBookIDs:initialBooks,context:ctx)
            if switched || existing.lastWallTime == nil{try await service.saveWallClock(Int64(Date().timeIntervalSince1970),context:ctx)}
            engine=service;context=ctx;state=await service.snapshot()
            if let s=state,s.mode == .offline {
                selectedID=s.instruments.first(where:{$0.currency==s.baseCurrency && !$0.asset.derivative && $0.asset != .index && $0.rules.isOpen(at:s.simulation!.time)})?.id ?? s.instruments.first?.id ?? ""
            }else{selectedID=state?.instruments.first(where:{$0.asset == .crypto})?.id ?? state?.instruments.first?.id ?? ""}
            restoreProductBrowsing()
            loadCredentialReadiness()
            settings.activeMode=target;settings.pendingMode=nil;try settings.save(root:root)
            var resources=URLResourceValues();resources.isExcludedFromBackup=true
            var url=root;try url.setResourceValues(resources)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:root.path)
            if !switched { await prepareCatchup() }
            lastUptime=ProcessInfo.processInfo.systemUptime
            if tab==2{await loadChart()}
            restartStream();await ensureQuoteService()
            if let link=settings.pendingNotice{await handleNoticeLink(link)}
        } catch { self.error=error.localizedDescription;booted=false }
    }
    func onboard(mode: Mode, online: String, offline: String, currency: String) async {
        await run {
            let amounts=[try Amount(online),try Amount(offline)]
            guard amounts.allSatisfy({$0 > .zero}) else { throw TradeError.invalid("初始本金必須大於零") }
            for (index,m) in Mode.allCases.enumerated() {
                let repo=try AccountRepository(root:self.root,mode:m)
                if try repo.load() == nil { try repo.save(TradingEngine.initial(mode:m,baseCurrency:currency,capital:amounts[index],time:Int64(Date().timeIntervalSince1970))) }
            }
            self.settings.activeMode=mode;self.settings.onboarded=true;try self.settings.save(root:self.root)
        }
        await boot()
    }
    func refresh() async {
        guard let engine else{return};state=await engine.snapshot()
        guard !notifying,state?.notificationEnabled==true,let context else{return}
        notifying=true;defer{notifying=false}
        do{let ids=try await notifications.deliver(state?.inbox ?? [],context:context);guard self.context==context,!ids.isEmpty else{return};try await engine.acknowledgeNotices(ids,context:context);state=await engine.snapshot()}catch{notice="系統通知未送達，事件仍保留於 App 內"}
    }
    func enableNotifications()async{
        guard let engine,let context else{return}
        do{let granted=try await notifications.requestPermission();try await engine.configureNotifications(granted,context:context);await refresh();if !granted{notice="通知權限未開啟；交易與 App 內事件中心仍可使用"}}catch{self.error=error.localizedDescription}
    }
    func select(_ instrument:Instrument){selectProduct(instrument)}
    func tick() async {
        guard !busy,foreground,let engine,let context,state != nil,progress == nil,clockWarning == nil,catchupTarget == nil else { return }
        if context.mode == .online{let clock=Int64(Date().timeIntervalSince1970);if marketClock != clock{marketClock=clock}}
        busy=true;defer{busy=false}
        let uptime=ProcessInfo.processInfo.systemUptime, elapsed=max(0,uptime-lastUptime);lastUptime=uptime
        do {
            if let sim=state?.simulation {
                if !sim.paused {
                    fractionalTime += elapsed*Double(sim.speed)
                    let seconds=Int64(fractionalTime)/5*5
                    if seconds > 0 {
                        let target=sim.time+seconds;fractionalTime -= Double(seconds)
                        var cursor=sim.time
                        while cursor < target && !Task.isCancelled && foreground && catchupTarget == nil { cursor=try await engine.advance(to:target,wallTarget:Int64(Date().timeIntervalSince1970),context:context) }
                        await refresh();await updateSimulatedSummaries()
                        if tab==2 { await loadChart() }
                    }
                }
            } else if uptime-lastFetch>=10 {
                lastFetch=uptime;await ensureQuoteService()
            }
        } catch { self.error=error.localizedDescription }
    }
    func suspend() async {
        foreground=false
        summaryTask?.cancel();summaryTask=nil;summaryAttemptedIDs=[];summaryMinute = -1;summaryGeneration=UUID()
        browseSaveTask?.cancel();await flushBrowsing()
        quoteServiceTask?.cancel();quoteServiceTask=nil;quoteServiceGeneration=UUID()
        if let context{await quoteScheduler.cancel(context:context)}
        candleTask?.cancel();candleTask=nil;boardQuoteTask?.cancel();boardQuoteTask=nil
        streamTask?.cancel();streamTask=nil
        guard let engine,let context else{return}
        if catchupTarget != nil || progress != nil{stopCatchup();return}
        await run {
            try await engine.saveWallClock(Int64(Date().timeIntervalSince1970),context:context)
            if context.mode == .online {for id in self.state?.quotes.keys.sorted() ?? []{try await engine.markMonitoringGap(instrumentID:id,time:Int64(Date().timeIntervalSince1970),context:context)}}
        }
    }
    func resume() async {
        guard !foreground else{return};foreground=true;lastUptime=ProcessInfo.processInfo.systemUptime
        await prepareCatchup()
        restartStream();await ensureQuoteService()
    }
    func restartStream() {
        streamTask?.cancel();streamTask=nil
        guard foreground,let i=selected,i.provider == .coinbase,context?.mode == .online,let context,let engine else{return}
        streamTask=Task{
            var attempts=0
            while !Task.isCancelled && self.foreground && self.context==context && self.selectedID==i.id {
                do{
                    let stream=try CoinbaseMarketStream(mode:.online).quotes(instrument:i)
                    for try await quote in stream {
                        guard !Task.isCancelled,self.foreground,self.context==context else{return}
                        try await engine.ingest(quote,now:Int64(Date().timeIntervalSince1970),context:context)
                        self.providerStatus[.coinbase]="WebSocket level2 已同步；本機估算成交"
                        attempts=0;await self.refresh()
                    }
                }catch{
                    guard !Task.isCancelled else{return}
                    self.providerStatus[.coinbase]=error.localizedDescription
                    try? await engine.markMonitoringGap(instrumentID:i.id,time:Int64(Date().timeIntervalSince1970),expectedSourcePrefix:"Coinbase Exchange WS",context:context)
                    await self.refresh()
                }
                attempts+=1
                do{try await Task.sleep(for:.seconds(min(60,pow(2,Double(min(attempts,6))))+Double.random(in:0...1)))}catch{return}
            }
        }
    }
    private func prepareCatchup() async {
        guard let s=state,let sim=s.simulation,!sim.paused,s.continueWhileAway,let wall=s.lastWallTime else{return}
        let delta=Int64(Date().timeIntervalSince1970)-wall
        if delta<0 || delta>604800 { clockWarning="裝置時間倒退或相隔超過七天。原檢查點保留，請明確選擇補算或從此刻繼續。";catchupTarget=sim.time+max(0,delta);return }
        if delta>=5 { catchupTarget=sim.time+delta;await catchUp() }
    }
    func catchUp() async {
        guard !catchingUp,let target=catchupTarget,let engine,let context,let start=state?.simulation?.time else{return}
        catchingUp=true;clockWarning=nil;progress=0
        defer{catchingUp=false;progress=nil;lastUptime=ProcessInfo.processInfo.systemUptime}
        do {
            var cursor=start
            let wallTarget=Int64(Date().timeIntervalSince1970)
            while cursor+5<=target && !Task.isCancelled && progress != nil {
                #if DEBUG
                await UITestSupport.checkpoint()
                #endif
                guard progress != nil else{break}
                cursor=try await engine.advance(to:target,wallTarget:wallTarget,catchup:true,context:context)
                guard progress != nil else{await refresh();break}
                progress=Double(cursor-start)/Double(max(1,target-start))
                // Simulation, ledger and corresponding wall anchor commit in the same transaction.
                await refresh();await Task.yield()
            }
            if progress != nil && cursor+5>target {
                catchupTarget=nil;notice="離線市場補算完成；事件時間為模擬時間"
                try await engine.recordNotice("catchupComplete",message:"離線市場補算完成；非背景即時推播",time:cursor,context:context)
                await refresh()
                if foreground{await loadChart()}
            }
        } catch { self.error=error.localizedDescription }
    }
    func stopCatchup() { progress=nil }
    func nextSession() async {
        guard let i=selected,let sim=state?.simulation else{return}
        if i.rules.isOpen(at:sim.time){notice="目前已在此商品的交易時段";return}
        var candidate=(sim.time/60+1)*60
        for _ in 0..<20160 {
            if i.rules.isOpen(at:candidate){catchupTarget=candidate;await catchUp();return}
            candidate+=60
        }
        error="未在接下來 14 天找到有效時段，請核對交易日曆或到期狀態"
    }
    func skipCatchup() async {
        catchupTarget=nil;clockWarning=nil;progress=nil
        if let engine,let context { await run{try await engine.saveWallClock(Int64(Date().timeIntervalSince1970),context:context)} }
    }
    func provider(_ id: ProviderID) throws -> MarketDataProvider {
        guard context?.mode == .online else { throw TradeError.invalid("B 不取得憑證或建立 Provider") }
        let credentials=try id.needsKey ? ProviderCredentials(key:KeychainVault.read(id.rawValue+".key"),secret:KeychainVault.read(id.rawValue+".secret")):ProviderCredentials()
        return try MarketDataProvider(id:id,credentials:credentials,transport:ReadOnlyTransport(mode:.online))
    }
    func fetchQuotes()async{
        guard context?.mode == .online else{return}
        await quoteScheduler.retry(requiredQuoteIDs)
        await ensureQuoteService()
    }
    func saveChartPreferences(indicator:String,period:Int,line:Bool)async{
        guard let engine,let context,!selectedID.isEmpty else{return}
        await run{try await engine.saveChartPreferences(instrumentID:self.selectedID,preferences:ChartPreferences(interval:self.interval,indicator:indicator,period:period,line:line),context:context)}
    }
    func captureChart()async{
        guard let web=chartWebView,let context else{error="圖表尚未準備完成";return}
        let id=selectedID,time=now
        do{
            let image:UIImage=try await withCheckedThrowingContinuation{continuation in web.takeSnapshot(with:nil){image,error in if let image{continuation.resume(returning:image)}else{continuation.resume(throwing:error ?? TradeError.unavailable("本機圖表截圖失敗"))}}}
            guard self.context==context,self.selectedID==id else{return}
            let format=UIGraphicsImageRendererFormat();format.scale=1
            let renderer=UIGraphicsImageRenderer(size:CGSize(width:image.size.width,height:image.size.height+48),format:format)
            let marked=renderer.image{ctx in UIColor.systemBackground.setFill();ctx.fill(CGRect(x:0,y:0,width:image.size.width,height:image.size.height+48));image.draw(at:CGPoint(x:0,y:48));let title="ChaiTrade · 模擬交易 · \(context.accountID)\n\(id) · \(time)";title.draw(in:CGRect(x:8,y:4,width:image.size.width-16,height:42),withAttributes:[.font:UIFont.monospacedSystemFont(ofSize:10,weight:.medium),.foregroundColor:UIColor.label])}
            guard let png=marked.pngData(),png.count<=2_000_000 else{throw TradeError.invalid("截圖超過 2 MB，請縮小圖表後重試")}
            journalScreenshot=png;notice="已保存本機圖表草稿，可於資產 → 交易日誌附加；尚未匯出至外部"
        }catch{self.error=error.localizedDescription}
    }
    func loadEarlierChart()async{
        if chartCount<1000{chartCount=min(1000,chartCount+160)}else if let first=candles.first{chartBefore=first.time-1;chartCount=160}
        await loadChart()
    }
    func loadLatestChart()async{chartBefore=nil;chartCount=160;await loadChart()}
    func loadChart() async {
        guard let i=selected,let s=state,let capturedContext=context else{return}
        candleTask?.cancel()
        let generation=UUID();chartGeneration=generation;chartError=nil;chartLimitation=nil;chartLoading=true
        defer{if generation==chartGeneration{chartLoading=false}}
        let interval=interval,count=chartCount,before=chartBefore,board=selectedBoard
        do {
            let task:Task<MarketHistoryResult,Error>
            var cacheKey:String?
            if s.simulation != nil,let engine {
                task=Task{MarketHistoryResult(candles:try await engine.simulationCandles(instrumentID:i.id,interval:interval,count:count,before:before,context:capturedContext))}
            } else if let id=i.provider {
                let key="\(s.accountID)|\(i.id)|\(board.rawValue)|\(interval)|\(before ?? 0)",service=try provider(id),now=Int64(Date().timeIntervalSince1970)
                let cached=chartCache[key] ?? [],cachedLimitation=chartCacheLimitations[key];cacheKey=key
                task=Task{
                    var history=cached,limitation=cachedLimitation
                    if cachedLimitation==nil,!history.isEmpty,history.count<count,let first=history.first{
                        let older=try await service.chartHistory(i,interval:interval,count:count-history.count,now:now,before:first.time-1,board:i.usesTaiwanBoards ? board:nil)
                        history=older.candles+history;limitation=older.limitation
                    }
                    let head=try await service.chartHistory(i,interval:interval,count:history.isEmpty ? count:min(count,160),now:now,before:before,board:i.usesTaiwanBoards ? board:nil)
                    try Task.checkCancellation()
                    var merged=Dictionary(history.map{($0.time,$0)},uniquingKeysWith:{_,new in new})
                    for candle in head.candles{merged[candle.time]=candle}
                    return MarketHistoryResult(candles:Array(merged.values.sorted{$0.time<$1.time}.suffix(count)),limitation:head.limitation ?? limitation)
                }
            } else {throw TradeError.unavailable("尚無圖表來源")}
            candleTask=task
            let result=try await withTaskCancellationHandler(operation:{try await task.value},onCancel:{task.cancel()})
            try Task.checkCancellation()
            guard generation==chartGeneration,self.context==capturedContext,self.selectedID==i.id else{return}
            if let key=cacheKey{
                chartCache[key]=result.candles;chartCacheLimitations[key]=result.limitation;chartCacheOrder.removeAll{$0==key};chartCacheOrder.append(key)
                while chartCacheOrder.count>8{let old=chartCacheOrder.removeFirst();chartCache.removeValue(forKey:old);chartCacheLimitations.removeValue(forKey:old)}
            }
            candles=result.candles;chartLimitation=result.limitation
            if result.candles.isEmpty{chartError="此範圍沒有行情，請切換週期或載入更多歷史"}
        } catch is CancellationError {} catch {
            if generation==chartGeneration,self.context==capturedContext,self.selectedID==i.id{candles=[];chartError=error.localizedDescription}
        }
    }
    func clearChartCaches(){chartGeneration=UUID();candleTask?.cancel();chartLimitation=nil;chartCache.removeAll();chartCacheLimitations.removeAll();chartCacheOrder.removeAll();Simulation.clearChartCache()}
    func rebindRestoredAccount()async throws{
        guard let previous=engine,let old=context else{throw TradeError.wrongAccount}
        quoteServiceTask?.cancel();quoteServiceTask=nil;quoteServiceGeneration=UUID();boardQuoteTask?.cancel();browseSaveTask?.cancel();browsingDirty=[];summaryTask?.cancel();summaryTask=nil;summaryAttemptedIDs=[];summaryMinute = -1;summaryGeneration=UUID()
        await quoteScheduler.cancel(context:old);try await previous.retire(context:old)
        let snapshot=await previous.snapshot(),next=AccountContext(mode:old.mode),root=self.root
        do{
            let replacement=try await Task.detached{try TradingEngine(context:next,repository:AccountRepository(root:root,mode:next.mode),initial:snapshot,wallClock:{Int64(Date().timeIntervalSince1970)})}.value
            try await replacement.prepareProductExperience(context:next);try await replacement.initializeQuotes(context:next)
            engine=replacement;context=next;state=await replacement.snapshot();clearChartCaches();restoreProductBrowsing();loadCredentialReadiness();stateRevision=UUID();restartStream()
        }catch{engine=nil;context=nil;state=nil;booted=false;throw error}
    }
    func submit(_ request:OrderRequest,oco:OrderRequest?=nil,expectedContext:AccountContext?=nil)async->OrderSubmissionOutcome{
        guard !interactionBlocked else{return .rejected("市場事件尚未處理完成，暫停新的委託")}
        guard let engine,let context else{return .rejected("帳戶尚未準備完成")}
        guard expectedContext==nil || expectedContext==context else{return .rejected("帳戶已變更，請重新開啟委託面板")}
        #if DEBUG
        await UITestSupport.submissionDelay()
        #endif
        guard !interactionBlocked else{return .rejected("市場事件處理中，暫停新的委託")}
        guard self.context==context else{return .rejected("帳戶已變更，未送出委託")}
        if context.mode == .online,let instrument=state?.instruments.first(where:{$0.id==request.instrumentID}),!canTrade(instrument,board:instrument.board(for:request)){return .rejected("行情或交易條件已變更，請重新確認有效報價後再送出")}
        do{
            if let oco{try await engine.submitOCO(request,oco,time:self.now,context:context)}else{_=try await engine.submit(request,time:self.now,context:context)}
            notice="委託已送入本機引擎；成交與保留請見委託頁";await refresh();return .accepted
        }catch{
            let message=error.localizedDescription
            if self.context==context{try? await engine.recordNotice("rejected",message:"委託拒絕："+String(message.prefix(250)),time:now,context:context);await refresh()}
            return .rejected(message)
        }
    }

    func setPending(_ mode: Mode?) {
        do { settings.pendingMode=mode == settings.activeMode ? nil:mode;if settings.pendingNotice?.mode != settings.pendingMode{settings.pendingNotice=nil};try settings.save(root:root) }
        catch { self.error=error.localizedDescription }
    }
    func saveSettings() { do{try settings.save(root:root)}catch{self.error=error.localizedDescription} }
    func configureSimulation(speed: Int? = nil, paused: Bool? = nil, scenario: String? = nil, volatility: Double? = nil, liquidity: Double? = nil) async {
        guard let sim=state?.simulation,let engine,let context else{return}
        await run{try await engine.configureSimulation(speed:speed ?? sim.speed,paused:paused ?? sim.paused,scenario:scenario ?? sim.scenario,volatility:volatility ?? sim.volatility,liquidity:liquidity ?? sim.liquidity,context:context)}
    }
    func toggleWatch(_ id: String) async {
        guard let engine,let context else{return}
        await run{try await engine.toggleWatch(id,context:context)}
    }
    func saveJournal(_ entry:JournalEntry)async->Bool{
        guard let engine,let context else{error="帳戶尚未準備完成";return false}
        return await run{try await engine.recordJournal(entry,context:context)}
    }

    func export(kind: String, password: String = "") async {
        guard let s=state,let engine,let context,!exportingWork else{return}
        exportingWork=true;defer{exportingWork=false}
        await run {
            let data: Data
            switch kind {
            case "CSV": data=try await engine.exportCSV(kind:"fills",time:self.now,context:context)
            case "ledger": data=try await engine.exportCSV(kind:"ledger",time:self.now,context:context)
            case "orders": data=try await engine.exportCSV(kind:"orders",time:self.now,context:context)
            case "both":
                let otherMode: Mode=s.mode == .online ? .offline:.online
                let root=self.root
                let other=try await Task.detached{let repository=try AccountRepository(root:root,mode:otherMode);guard let full=try repository.fullSnapshot(maximumExpandedBytes:BackupService.legacyExpandedLimit) else{throw TradeError.corrupt("另一帳戶不存在，完整備份中止")};return full}.value
                let full=try await engine.fullSnapshot(maximumExpandedBytes:BackupService.legacyExpandedLimit,context:context),time=self.now
                data=try await Task.detached{try BackupService.exportBoth([full,other],password:password.isEmpty ? nil:password,time:time)}.value
            case "JSON":
                var clean=try await engine.fullSnapshot(context:context);if s.mode == .online{clean.quotes=[:];clean.consumed=[:]};let full=clean
                data=try await Task.detached{try AccountRepository.encode(full)}.value
            default:
                let full=try await engine.fullSnapshot(maximumExpandedBytes:BackupService.legacyExpandedLimit,context:context),time=self.now
                data=try await Task.detached{try BackupService.export(full,password:password.isEmpty ? nil:password,time:time)}.value
            }
            self.exportName="ChaiTrade-模擬交易-\(s.accountID)-\(kind).\(["CSV","ledger","orders"].contains(kind) ? "csv":kind == "JSON" ? "json":"chaitrade")"
            self.exportDocument=ExportDocument(data:data);self.exporting=true
        }
    }
    func importBackup(_ url: URL, password: String) async {
        guard let context,let engine else{return}
        do{
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            if try StreamingArchiveService.recognizes(url){startFileArchiveRestore(url,password:password);return}
        }catch{self.error=error.localizedDescription;return}
        await run {
            let granted=url.startAccessingSecurityScopedResource();defer{if granted{url.stopAccessingSecurityScopedResource()}}
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=100_000_000 else{throw TradeError.corrupt("備份超過安全大小限制")}
            let data=try Data(contentsOf:url,options:.mappedIfSafe)
            let restored=try await Task.detached{try BackupService.importAccount(data,expectedMode:context.mode,password:password)}.value
            self.maintainingAccount=true;defer{self.maintainingAccount=false}
            let token=try await engine.beginFileMaintenance(snapshotAt:self.recoveryURL("before-restore",context:context),context:context)
            do{
            try await engine.restore(restored,maintenanceToken:token,retireAfterRestore:true,context:context);try await self.rebindRestoredAccount();self.notice="備份已驗證並原子還原；原帳戶已建立恢復點"
            }catch{try? await engine.endMaintenance(token:token,context:context);throw error}
        }
        await refresh();await ensureQuoteService()
        await loadChart()
    }
    func recoverFailedAccount(_ url: URL,password: String) async {
        guard state == nil,engine == nil,!loading else{return}
        loading=true
        do {
            let target=settings.pendingMode ?? settings.activeMode
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            if try StreamingArchiveService.recognizes(url){loading=false;startFailedFileArchiveRecovery(url,password:password,target:target);return}
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=100_000_000 else{throw TradeError.corrupt("備份超過安全大小限制")}
            let restored=try await Task.detached{try BackupService.importAccount(Data(contentsOf:url,options:.mappedIfSafe),expectedMode:target,password:password)}.value
            let stage=root.appendingPathComponent("recovery-stage-\(UUID().uuidString)")
            defer{try? FileManager.default.removeItem(at:stage)}
            do {let repository=try AccountRepository(root:stage,mode:target);try repository.save(restored,replacing:true)}
            let replacement=stage.appendingPathComponent("accounts/\(target.accountID)")
            try await finishFileRecovery(replacement:replacement,target:target)
        }catch{loading=false;self.error=error.localizedDescription}
    }
    func finishFileRecovery(replacement:URL,target:Mode)async throws{
        guard state==nil,engine==nil,target==(settings.pendingMode ?? settings.activeMode) else{throw TradeError.wrongAccount}
        let original=root.appendingPathComponent("accounts/\(target.accountID)")
        try FileManager.default.createDirectory(at:original.deletingLastPathComponent(),withIntermediateDirectories:true)
        if FileManager.default.fileExists(atPath:original.path){
            _=try FileManager.default.replaceItemAt(original,withItemAt:replacement,backupItemName:"preserved-\(target.accountID)-\(UUID().uuidString)",options:.usingNewMetadataOnly)
        }else{try FileManager.default.moveItem(at:replacement,to:original)}
        error=nil;notice="帳戶備份已驗證；舊目錄已保留，正在重新啟動本機服務"
        booted=false;loading=false;await boot()
    }
}
