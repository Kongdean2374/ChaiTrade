import Foundation

/// Foundation's Darwin file/crypto bridges can retain autoreleased buffers until
/// an entire synchronous archive operation returns. Drain each bounded work unit.
enum ArchiveMemory{
    static func scoped<T>(_ body:()throws->T)rethrows->T{
        #if canImport(ObjectiveC)
        return try autoreleasepool(invoking:body)
        #else
        return try body()
        #endif
    }
    static func read(_ handle:FileHandle,upToCount:Int)throws->Data?{try scoped{try handle.read(upToCount:upToCount)}}
}
