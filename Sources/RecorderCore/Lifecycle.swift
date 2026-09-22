import Foundation

/// Await every in-flight operation, including one that another caller already started.
@MainActor public final class CompletionGate {
    private var pending = Set<UUID>()
    private var waiters: [CheckedContinuation<Void,Never>] = []
    public init() {}
    public func begin() -> UUID { let id = UUID(); pending.insert(id); return id }
    public func end(_ id: UUID) {
        pending.remove(id)
        if pending.isEmpty { let ready = waiters; waiters = []; ready.forEach { $0.resume() } }
    }
    public func wait() async {
        guard !pending.isEmpty else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
/// Generation identity prevents an old stream callback from stopping a newer recording.
public struct CaptureAttempt {
    public private(set) var generation: UUID?
    public private(set) var failure: String?
    public init() {}
    public mutating func begin() -> UUID { let id = UUID(); generation = id; failure = nil; return id }
    public mutating func fail(_ message: String,generation id: UUID) { if generation == id && failure == nil { failure = message } }
    public mutating func end() { generation = nil }
}
