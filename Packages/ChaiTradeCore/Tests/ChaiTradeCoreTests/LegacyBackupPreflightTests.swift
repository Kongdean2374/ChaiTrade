import Foundation
import Testing
@testable import ChaiTradeCore

@Test func legacyBackupPreflightRejectsBeforeMaterializingAndDoesNotReduceProductionCap()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
    let repository=try AccountRepository(root:root,mode:.online)
    var state=try TradingEngine.initial(mode:.online,capital:Amount(2500),time:1000)
    for n in 0..<40{state.journals.append(JournalEntry(id:"preflight-\(n)",text:String(repeating:"原始日誌",count:1000),tags:"synthetic",time:1000))}
    _=try repository.save(state)
    #expect(BackupService.legacyExpandedLimit==512_000_000)
    let before=try repository.load()
    #expect(throws:TradeError.self){try repository.fullSnapshot(maximumExpandedBytes:1024)}
    #expect(try AccountRepository.encode(repository.load())==AccountRepository.encode(before))
    let full=try #require(try repository.fullSnapshot(maximumExpandedBytes:BackupService.legacyExpandedLimit))
    #expect(full.journals.count==40 && full.cash==state.cash)
    let backup=try BackupService.export(full,password:nil,time:1000)
    #expect(try BackupService.validate(backup,expectedMode:.online,password:nil).journals.count==40)
}
