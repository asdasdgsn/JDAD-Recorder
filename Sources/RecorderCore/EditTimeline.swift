import Foundation

public struct EditTimeline: Equatable, Sendable {
    public var kept: [TimeSpan]
    public init(kept: [TimeSpan]) { self.kept = kept }
    public var duration: Double { kept.reduce(0) { $0 + $1.duration } }
    public func sourceTime(at outputTime: Double) -> Double? {
        guard outputTime.isFinite, outputTime >= 0, outputTime < duration else { return nil }
        var cursor = 0.0
        for s in kept {
            if outputTime < cursor + s.duration { return s.start + outputTime - cursor }
            cursor += s.duration
        }
        return nil
    }
    public func outputTime(at sourceTime: Double) -> Double? {
        var cursor = 0.0
        for s in kept {
            if sourceTime >= s.start && sourceTime < s.end { return cursor + sourceTime - s.start }
            cursor += s.duration
        }
        return nil
    }
    public mutating func delete(outputRange: TimeSpan) {
        guard outputRange.start.isFinite, outputRange.end.isFinite, outputRange.end > outputRange.start else { return }
        let before = spans(in: .init(start: 0, end: max(0,outputRange.start)))
        let after = spans(in: .init(start: min(duration,outputRange.end), end: duration))
        kept = before + after
    }
    public mutating func retain(outputRange: TimeSpan) {
        guard outputRange.start.isFinite, outputRange.end.isFinite else { return }
        kept = spans(in: outputRange)
    }
    private func spans(in range: TimeSpan) -> [TimeSpan] {
        var cursor = 0.0
        var result: [TimeSpan] = []
        for s in kept {
            let a = max(cursor,range.start), b = min(cursor+s.duration,range.end)
            if b > a { result.append(.init(start: s.start+a-cursor,end: s.start+b-cursor)) }
            cursor += s.duration
        }
        return result
    }
}
public struct EditHistory {
    private var past: [Project] = []
    private var future: [Project] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func record(_ project: Project) { past.append(project); if past.count > 100 { past.removeFirst() }; future = [] }
    public mutating func undo(current: Project) -> Project? {
        guard let p = past.popLast() else { return nil }; future.append(current); return p
    }
    public mutating func redo(current: Project) -> Project? {
        guard let p = future.popLast() else { return nil }; past.append(current); return p
    }
}
