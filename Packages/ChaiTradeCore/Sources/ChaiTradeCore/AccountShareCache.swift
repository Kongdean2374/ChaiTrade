import Foundation

/// Only completed, app-owned archive files for one account; never account databases or recovery points.
public enum AccountShareCache{
    private static func directory(_ root:URL)throws->URL{
        guard root.isFileURL else{throw TradeError.invalid("分享暫存目錄無效")}
        let directory=root.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent("share-cache",isDirectory:true)
        guard directory.resolvingSymlinksInPath().standardizedFileURL==directory.standardizedFileURL else{throw TradeError.invalid("分享暫存不可指向其他目錄")}
        return directory
    }
    public static func completed(root:URL,mode:Mode)throws->[URL]{
        let folder=try directory(root),manager=FileManager.default
        guard manager.fileExists(atPath:folder.path) else{return []}
        let prefix="ChaiTrade-模擬交易-\(mode.accountID)-",suffix=".chaitradearchive"
        return try manager.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]).filter{url in
            let name=url.lastPathComponent
            guard name.hasPrefix(prefix),name.hasSuffix(suffix),UUID(uuidString:String(name.dropFirst(prefix.count).dropLast(suffix.count))) != nil else{return false}
            let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            return values.isRegularFile==true && values.isSymbolicLink != true
        }.sorted{$0.lastPathComponent<$1.lastPathComponent}
    }
    @discardableResult public static func clear(root:URL,mode:Mode)throws->Int{
        let files=try completed(root:root,mode:mode)
        for url in files{try Task.checkCancellation();try FileManager.default.removeItem(at:url)}
        return files.count
    }
}
