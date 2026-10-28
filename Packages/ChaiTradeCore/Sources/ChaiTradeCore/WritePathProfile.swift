#if CHAI_STORAGE_PROFILE
import Foundation

/// Compile-time diagnostic for synthetic CI storage runs only. The normal App
/// and acceptance builds contain none of this code. No identities or values log.
struct WritePathProfile {
    private let operation: String
    private let clock = ContinuousClock()
    private let started: ContinuousClock.Instant
    private var previous: ContinuousClock.Instant
    private var phases: [[String: Any]] = []
    init(_ operation: String) {
        self.operation = operation
        let now = ContinuousClock().now
        started = now; previous = now
    }
    private func seconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
        let value = start.duration(to: end).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
    mutating func mark(_ name: String) {
        let now = clock.now
        phases.append(["phase": name, "seconds": seconds(previous, now)])
        previous = now
    }
    func emit() {
        let record: [String: Any] = ["operation": operation, "seconds": seconds(started, clock.now), "phases": phases]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print("WRITE_PATH_PROFILE", text) }
    }
}
#endif
