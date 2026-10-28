import Foundation
import Testing
@testable import ChaiTradeCore

@Test func shareCacheListsCompletedFilesAcrossRestartAndClearsOnlyCurrentAccount()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),folder=root.appendingPathComponent("share-cache")
    defer{try? FileManager.default.removeItem(at:root)}
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    func archive(_ mode:Mode)->URL{folder.appendingPathComponent("ChaiTrade-模擬交易-\(mode.accountID)-\(UUID().uuidString).chaitradearchive")}
    let a=archive(.online),b=archive(.offline),unowned=folder.appendingPathComponent("keep.chaitradearchive"),partial=folder.appendingPathComponent(".partial-"+UUID().uuidString)
    let recovery=root.appendingPathComponent("accounts/account-online/snapshots/manual/account.sqlite")
    try FileManager.default.createDirectory(at:recovery.deletingLastPathComponent(),withIntermediateDirectories:true)
    for url in [a,b,unowned,partial,recovery]{try Data("synthetic-owned-file".utf8).write(to:url)}
    let symlink=archive(.online);try FileManager.default.createSymbolicLink(at:symlink,withDestinationURL:recovery)
    let directory=archive(.online);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    #expect(try AccountShareCache.completed(root:root,mode:.online).map{$0.resolvingSymlinksInPath()}==[a.resolvingSymlinksInPath()])
    #expect(try AccountShareCache.completed(root:root,mode:.offline).map{$0.resolvingSymlinksInPath()}==[b.resolvingSymlinksInPath()])
    #expect(try AccountShareCache.clear(root:root,mode:.online)==1)
    #expect(try AccountShareCache.completed(root:root,mode:.online).isEmpty)
    #expect(try AccountShareCache.completed(root:root,mode:.offline).map{$0.resolvingSymlinksInPath()}==[b.resolvingSymlinksInPath()])
    for url in [b,unowned,partial,recovery,symlink,directory]{#expect(FileManager.default.fileExists(atPath:url.path))}
    #expect(try Data(contentsOf:recovery)==Data("synthetic-owned-file".utf8))
}

@Test func shareCacheRejectsDirectorySymlinkWithoutDeletingItsTarget()throws{
    let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),outside=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer{try? FileManager.default.removeItem(at:root);try? FileManager.default.removeItem(at:outside)}
    try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:true)
    let file=outside.appendingPathComponent("ChaiTrade-模擬交易-\(Mode.online.accountID)-\(UUID().uuidString).chaitradearchive");try Data([1,2,3]).write(to:file)
    try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("share-cache"),withDestinationURL:outside)
    #expect(throws:TradeError.self){try AccountShareCache.clear(root:root,mode:.online)}
    #expect(try Data(contentsOf:file)==Data([1,2,3]))
}
