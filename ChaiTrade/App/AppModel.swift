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
    @Published var state: AccountState?
    @Published var settings=AppSettings()
    @Published var error: String?
    @Published var notice: String?
    @Published var loading=false
    @Published var progress: Double?
    @Published var selectedID=""
    @Published var tab=0
    @Published var stateRevision=UUID()
    @Published var candles: [Candle]=[]
    @Published var chartError: String?
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
    @Published var catchupTarget: Int64?
    @Published var clockWarning: String?
    @Published var chartAmendment: ChartAmendment?
    private(set) var engine: TradingEngine?
    private(set) var context: AccountContext?
    private let notifications=LocalNotifications()
    private var notifying=false
    private var booted=false
    private var busy=false
    private var foreground=true
    private var lastUptime=ProcessInfo.processInfo.systemUptime
    private var fractionalTime=0.0
    private var lastFetch=0.0
    private var chartGeneration=UUID()
    private var candleTask:Task<[Candle],Error>?
    private var chartCache:[String:[Candle]]=[:]
    private var chartCacheOrder:[String]=[]
    private var streamTask: Task<Void,Never>?
    let root: URL
    init() {
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        root=base.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--uitest") ? "ChaiTradeUITest":"ChaiTrade",isDirectory:true)
        do { settings=try AppSettings.load(root:root) } catch { self.error="設定檔無法讀取，保留原資料：\(error.localizedDescription)" }
    }
    var now: Int64 { state?.simulation?.time ?? Int64(Date().timeIntervalSince1970) }
    var selected: Instrument? { state?.instruments.first { $0.id == selectedID } }
    var quote: Quote? { state?.quotes[selectedID] }
    var valuation: Valuation? { state.flatMap { try? Analytics.valuation($0) } }
    func money(_ value: Amount?) -> String { settings.hideBalances ? "••••••" : value?.description ?? "未提供" }
    func run(_ operation: () async throws -> Void) async {
        do { try await operation();await refresh() } catch { self.error=error.localizedDescription }
    }
    func boot() async {
        guard !booted,settings.onboarded else { return }
        booted=true;loading=true;defer{loading=false}
        do {
            let target=settings.pendingMode ?? settings.activeMode
            let switched=target != settings.activeMode
            let ctx=AccountContext(mode:target),root=self.root
            let (existing,service)=try await Task.detached{let repo=try AccountRepository(root:root,mode:target);guard let existing=try repo.load() else{throw TradeError.corrupt("帳戶不存在，請使用備份恢復；不會重建空帳戶覆蓋資料")};let service=try TradingEngine(context:ctx,repository:repo,initial:existing,wallClock:{Int64(Date().timeIntervalSince1970)});return (existing,service)}.value
            try await service.initializeQuotes(context:ctx)
            if switched || existing.lastWallTime == nil{try await service.saveWallClock(Int64(Date().timeIntervalSince1970),context:ctx)}
            engine=service;context=ctx;state=await service.snapshot()
            if let s=state,s.mode == .offline {
                selectedID=s.instruments.first(where:{$0.currency==s.baseCurrency && !$0.asset.derivative && $0.asset != .index && $0.rules.isOpen(at:s.simulation!.time)})?.id ?? s.instruments.first?.id ?? ""
            }else{selectedID=state?.instruments.first(where:{$0.asset == .crypto})?.id ?? state?.instruments.first?.id ?? ""}
            settings.activeMode=target;settings.pendingMode=nil;try settings.save(root:root)
            var resources=URLResourceValues();resources.isExcludedFromBackup=true
            var url=root;try url.setResourceValues(resources)
            try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:root.path)
            if !switched { await prepareCatchup() }
            lastUptime=ProcessInfo.processInfo.systemUptime
            await loadChart()
            restartStream()
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
    func select(_ instrument: Instrument) { selectedID=instrument.id;chartBefore=nil;chartCount=160;tab=2;restartStream();Task{await loadChart()} }
    func tick() async {
        guard !busy,foreground,let engine,let context,state != nil,progress == nil,clockWarning == nil,catchupTarget == nil else { return }
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
                        while cursor < target && !Task.isCancelled { cursor=try await engine.advance(to:target,wallTarget:Int64(Date().timeIntervalSince1970),context:context) }
                        await refresh()
                        if tab==2 { await loadChart() }
                    }
                }
            } else if uptime-lastFetch>=10 {
                lastFetch=uptime;await fetchQuotes()
            }
        } catch { self.error=error.localizedDescription }
    }
    func suspend() async {
        foreground=false
        candleTask?.cancel();candleTask=nil
        streamTask?.cancel();streamTask=nil
        guard let engine,let context else{return}
        await run {
            try await engine.saveWallClock(Int64(Date().timeIntervalSince1970),context:context)
            if context.mode == .online {for id in self.state?.quotes.keys.sorted() ?? []{try await engine.markMonitoringGap(instrumentID:id,time:Int64(Date().timeIntervalSince1970),context:context)}}
        }
    }
    func resume() async {
        guard !foreground else{return};foreground=true;lastUptime=ProcessInfo.processInfo.systemUptime
        await prepareCatchup()
        restartStream()
    }
    private func restartStream() {
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
                    try? await engine.markMonitoringGap(instrumentID:i.id,time:Int64(Date().timeIntervalSince1970),context:context)
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
        guard let target=catchupTarget,let engine,let context,let start=state?.simulation?.time else{return}
        clockWarning=nil;progress=0
        do {
            var cursor=start
            let wallTarget=Int64(Date().timeIntervalSince1970)
            while cursor+5<=target && !Task.isCancelled && progress != nil {
                cursor=try await engine.advance(to:target,wallTarget:wallTarget,catchup:true,context:context)
                progress=Double(cursor-start)/Double(max(1,target-start))
                // Simulation, ledger and corresponding wall anchor commit in the same transaction.
                await refresh();await Task.yield()
            }
            if cursor+5>target { catchupTarget=nil;notice="離線市場補算完成；事件時間為模擬時間";try await engine.recordNotice("catchupComplete",message:"離線市場補算完成；非背景即時推播",time:cursor,context:context);await refresh() }
        } catch { self.error=error.localizedDescription }
        progress=nil;lastUptime=ProcessInfo.processInfo.systemUptime
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
        let credentials=try ProviderCredentials(key:KeychainVault.read(id.rawValue+".key"),secret:KeychainVault.read(id.rawValue+".secret"))
        return try MarketDataProvider(id:id,credentials:credentials,transport:ReadOnlyTransport(mode:.online))
    }
    func fetchQuotes() async {
        guard !fetching,let s=state,s.mode == .online,let context,let engine else{return}
        fetching=true;defer{fetching=false}
        var ids=s.watchlist.union(s.positions.values.filter{$0.quantity != .zero}.map(\.id))
        ids.formUnion(s.orders.values.filter{$0.status.open}.map{$0.request.instrumentID});ids.insert(selectedID)
        ids.formUnion(s.alerts.filter{$0.firedAt == nil}.map(\.instrumentID))
        for i in s.instruments where ids.contains(i.id) {
            guard foreground,let id=i.provider else{continue}
            if i.provider == .coinbase,i.id==selectedID,let q=s.quotes[i.id],q.source.hasPrefix("Coinbase Exchange WS"),q.valid,Int64(Date().timeIntervalSince1970)-q.receivedAt<10{continue}
            do {
                let service=try provider(id),received=Int64(Date().timeIntervalSince1970)
                let q=try await service.quote(i,now:received)
                guard self.context == context,foreground else { continue }
                try await engine.ingest(q,now:Int64(Date().timeIntervalSince1970),context:context)
                providerStatus[id]="\(q.quality.rawValue)・\(q.grade.rawValue)・\(q.coverage)"
            } catch { providerStatus[id]=error.localizedDescription;try? await engine.markMonitoringGap(instrumentID:i.id,time:Int64(Date().timeIntervalSince1970),context:context) }
        }
        await refresh()
        if tab==2 { await loadChart() }
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
        guard let i=selected,let s=state else{return}
        let generation=UUID();chartGeneration=generation;chartError=nil;chartLoading=true
        defer{if generation==chartGeneration{chartLoading=false}}
        let interval=interval,count=chartCount,before=chartBefore
        do {
            let values: [Candle]
            if let sim=s.simulation { candleTask?.cancel();let task=Task.detached(priority:.userInitiated){try Simulation.candles(i,state:sim,interval:interval,count:count,before:before)};candleTask=task;values=try await task.value }
            else if let id=i.provider {
                let key="\(s.accountID)|\(i.id)|\(interval)|\(before ?? 0)",service=try provider(id),now=Int64(Date().timeIntervalSince1970)
                var cached=chartCache[key] ?? []
                if !cached.isEmpty,cached.count<count,let first=cached.first{
                    let older=try await service.history(i,interval:interval,count:count-cached.count,now:now,before:first.time-1)
                    cached=older+cached
                }
                let head=try await service.history(i,interval:interval,count:cached.isEmpty ? count:min(count,160),now:now,before:before)
                var merged=Dictionary(cached.map{($0.time,$0)},uniquingKeysWith:{_,new in new});for c in head{merged[c.time]=c}
                values=Array(merged.values.sorted{$0.time<$1.time}.suffix(count))
                chartCache[key]=values;chartCacheOrder.removeAll{$0==key};chartCacheOrder.append(key)
                while chartCacheOrder.count>8{chartCache.removeValue(forKey:chartCacheOrder.removeFirst())}
                if values.count<cached.count || (cached.count<count && values.count==cached.count){notice="來源沒有提供更早的可用歷史；不產生替代 K 線"}
            }
            else { throw TradeError.unavailable("尚無圖表來源") }
            guard generation==chartGeneration else{return};candles=values
            if values.isEmpty { chartError="此範圍沒有行情，請切換週期或載入更多歷史" }
        } catch is CancellationError {} catch { if generation==chartGeneration { candles=[];chartError=error.localizedDescription } }
    }
    func clearChartCaches(){candleTask?.cancel();chartCache.removeAll();chartCacheOrder.removeAll();Simulation.clearChartCache()}
    func submit(_ request: OrderRequest, oco: OrderRequest? = nil) async {
        guard let engine,let context else{return}
        do{
            if let oco{try await engine.submitOCO(request,oco,time:self.now,context:context)}else{_=try await engine.submit(request,time:self.now,context:context)}
            notice="委託已送入本機引擎；成交與保留請見委託頁";await refresh()
        }catch{
            let message=error.localizedDescription
            if self.context==context{try? await engine.recordNotice("rejected",message:"委託拒絕："+String(message.prefix(250)),time:now,context:context);await refresh()}
            self.error=message
        }
    }

    func setPending(_ mode: Mode?) {
        do { settings.pendingMode=mode == settings.activeMode ? nil:mode;try settings.save(root:root) }
        catch { self.error=error.localizedDescription }
    }
    func saveSettings() { do{try settings.save(root:root)}catch{self.error=error.localizedDescription} }
    func configureSimulation(speed: Int? = nil, paused: Bool? = nil, scenario: String? = nil, volatility: Double? = nil, liquidity: Double? = nil) async {
        guard let sim=state?.simulation,let engine,let context else{return}
        await run{try await engine.configureSimulation(speed:speed ?? sim.speed,paused:paused ?? sim.paused,scenario:scenario ?? sim.scenario,volatility:volatility ?? sim.volatility,liquidity:liquidity ?? sim.liquidity,context:context)}
    }
    func toggleWatch(_ id: String) async {
        guard var set=state?.watchlist,let engine,let context else{return}
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        let updated=set;await run{try await engine.updatePreferences(watchlist:updated,context:context)}
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
                let other=try await Task.detached{let repository=try AccountRepository(root:root,mode:otherMode);guard let full=try repository.fullSnapshot() else{throw TradeError.corrupt("另一帳戶不存在，完整備份中止")};return full}.value
                let full=try await engine.fullSnapshot(context:context),time=self.now
                data=try await Task.detached{try BackupService.exportBoth([full,other],password:password.isEmpty ? nil:password,time:time)}.value
            case "JSON":
                var clean=try await engine.fullSnapshot(context:context);if s.mode == .online{clean.quotes=[:];clean.consumed=[:]};let full=clean
                data=try await Task.detached{try AccountRepository.encode(full)}.value
            default:
                let full=try await engine.fullSnapshot(context:context),time=self.now
                data=try await Task.detached{try BackupService.export(full,password:password.isEmpty ? nil:password,time:time)}.value
            }
            self.exportName="ChaiTrade-模擬交易-\(s.accountID)-\(kind).\(["CSV","ledger","orders"].contains(kind) ? "csv":kind == "JSON" ? "json":"chaitrade")"
            self.exportDocument=ExportDocument(data:data);self.exporting=true
        }
    }
    func importBackup(_ url: URL, password: String) async {
        guard let context,let engine else{return}
        await run {
            let granted=url.startAccessingSecurityScopedResource();defer{if granted{url.stopAccessingSecurityScopedResource()}}
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=100_000_000 else{throw TradeError.corrupt("備份超過安全大小限制")}
            let data=try Data(contentsOf:url,options:.mappedIfSafe)
            let restored=try await Task.detached{try BackupService.importAccount(data,expectedMode:context.mode,password:password)}.value
            self.maintainingAccount=true;defer{self.maintainingAccount=false}
            let (token,current)=try await engine.beginMaintenance(context:context)
            do{
            let time=self.now
            let recovery=try await Task.detached{try BackupService.export(current,password:nil,time:time)}.value
            let directory=self.root.appendingPathComponent("accounts/\(context.accountID)/snapshots")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try recovery.write(to:directory.appendingPathComponent("before-restore-\(Date().timeIntervalSince1970).chaitrade"),options:.atomic)
            try await engine.restore(restored,maintenanceToken:token,context:context);self.clearChartCaches();self.stateRevision=UUID();self.notice="備份已驗證並原子還原；原帳戶已建立恢復點"
            }catch{try? await engine.endMaintenance(token:token,context:context);throw error}
        }
        await loadChart()
    }
    func recoverFailedAccount(_ url: URL,password: String) async {
        guard state == nil,engine == nil,!loading else{return}
        loading=true
        do {
            let target=settings.pendingMode ?? settings.activeMode
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            let size=try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard size<=100_000_000 else{throw TradeError.corrupt("備份超過安全大小限制")}
            let restored=try await Task.detached{try BackupService.importAccount(Data(contentsOf:url,options:.mappedIfSafe),expectedMode:target,password:password)}.value
            let stage=root.appendingPathComponent("recovery-stage-\(UUID().uuidString)")
            defer{try? FileManager.default.removeItem(at:stage)}
            do {let repository=try AccountRepository(root:stage,mode:target);try repository.save(restored,replacing:true)}
            let replacement=stage.appendingPathComponent("accounts/\(target.accountID)")
            let original=root.appendingPathComponent("accounts/\(target.accountID)")
            if FileManager.default.fileExists(atPath:original.path) {
                _=try FileManager.default.replaceItemAt(original,withItemAt:replacement,backupItemName:"preserved-\(target.accountID)-\(UUID().uuidString)",options:.usingNewMetadataOnly)
            }else{try FileManager.default.moveItem(at:replacement,to:original)}
            error=nil;notice="帳戶備份已驗證；舊目錄已保留，正在重新啟動本機服務"
            booted=false;loading=false;await boot()
        }catch{loading=false;self.error=error.localizedDescription}
    }
}
