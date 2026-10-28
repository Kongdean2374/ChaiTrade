import Foundation
import Testing
@testable import ChaiTradeCore

@Test func draftSurvivesBrowsingRefreshRestartAndRejectsLateAutosaveOrWrongIdentity()async throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),ctx=AccountContext(mode:.offline)
    defer{try? FileManager.default.removeItem(at:root)}
    let initial=try TradingEngine.initial(mode:.offline,capital:Amount("1000000"),time:1730772000),repo=try AccountRepository(root:root,mode:.offline)
    let engine=try TradingEngine(context:ctx,repository:repo,initial:initial)
    let before=await engine.snapshot(),first=try #require(before.instruments.first{$0.asset == .crypto}),second=try #require(before.instruments.first{$0.asset == .taiwanStock})
    var workspace=TradeWorkspace(accountID:ctx.accountID,instrument:first,side:.sell)
    var fields=TradeEditor();fields.side = .sell;fields.quantity="0.173";fields.price="12345";workspace.editor=fields
    try await engine.saveTradeWorkspace(workspace,context:ctx)
    var browse=MarketBrowsingState();browse.selectedID=second.id;browse.search="2330"
    try await engine.saveMarketBrowsing(browse,market:.stocks,activate:true,context:ctx)
    for _ in 0..<8{let read=try await engine.marketSnapshot(context:ctx);#expect(read.productPreferences?.tradeWorkspace==workspace);#expect(read.simulation?.time==before.simulation?.time);#expect(read.quotes==before.quotes)}
    let saved=try #require(try repo.load());#expect(saved.productPreferences?.tradeWorkspace==workspace)
    #expect(saved.cash==before.cash);#expect(saved.orders.isEmpty);#expect(saved.fills.isEmpty)
    let backup=try BackupService.export(saved,password:"draft-backup-test",time:before.simulation!.time)
    let restored=try BackupService.validate(backup,expectedMode:.offline,password:"draft-backup-test")
    #expect(restored.productPreferences?.tradeWorkspace==workspace)
    var foreign=workspace;foreign.accountID=Mode.online.accountID
    await #expect(throws:TradeError.self){try await engine.saveTradeWorkspace(foreign,context:ctx)}
    var next=TradeWorkspace(accountID:ctx.accountID,instrument:second,revision:2)
    try await engine.saveTradeWorkspace(next,context:ctx)
    try await engine.saveTradeWorkspace(workspace,context:ctx)
    #expect(await engine.snapshot().productPreferences?.tradeWorkspace==next)
    next.product.currency="WRONG";next.revision=3
    await #expect(throws:TradeError.self){try await engine.saveTradeWorkspace(next,context:ctx)}
    await #expect(throws:TradeError.self){try await engine.saveTradeWorkspace(workspace,context:AccountContext(mode:.offline))}
    var corrupt=saved;corrupt.productPreferences!.tradeWorkspace!.product.exchange="wrong venue"
    #expect(throws:TradeError.self){try AccountRepository.validate(corrupt,mode:.offline)}
    try await engine.retire(context:ctx)
    await #expect(throws:TradeError.self){try await engine.marketSnapshot(context:ctx)}
}

@Test func previousPreferencesWithoutATradeWorkspaceStillDecode()throws{
    let old=Data(#"{"version":1,"activeMarket":"stocks","markets":{},"groups":[],"catalogMigrated":true}"#.utf8)
    let preferences=try JSONDecoder().decode(ProductPreferences.self,from:old)
    #expect(preferences.tradeWorkspace==nil);#expect(preferences.catalogMigrated)
}
