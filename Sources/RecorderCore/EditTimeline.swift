import Foundation

public struct EditTimeline: Equatable, Sendable {
    public var kept: [TimeSpan]
    public init(kept: [TimeSpan]) { self.kept = kept }
    public var duration: Double { kept.reduce(0) { $0 + $1.duration } }
    public var boundaries: [Double] {
        var result = [0.0]
        for span in kept { result.append(result.last! + span.duration) }
        return result
    }
    @discardableResult public mutating func split(at outputTime: Double) -> Bool {
        guard outputTime.isFinite else { return false }
        let time = (outputTime * 30).rounded() / 30
        var cursor = 0.0
        for (index,span) in kept.enumerated() {
            let local = time-cursor
            if local >= 1.0/30-0.000001 && span.duration-local >= 1.0/30-0.000001 {
                let cut = span.start+local
                kept.replaceSubrange(index...index,with:[.init(start:span.start,end:cut),.init(start:cut,end:span.end)])
                return true
            }
            cursor += span.duration
        }
        return false
    }
    /// Destination is a boundary in the original array, before removing the moving clip.
    @discardableResult public mutating func moveClip(from index: Int,toBoundary boundary: Int) -> Bool {
        guard kept.indices.contains(index), (0...kept.count).contains(boundary), boundary != index, boundary != index+1 else { return false }
        let clip = kept.remove(at:index)
        kept.insert(clip,at:boundary > index ? boundary-1 : boundary)
        return true
    }
    public func insertionBoundary(at time: Double) -> Int {
        boundaries.enumerated().min(by:{ abs($0.element-time) < abs($1.element-time) })?.offset ?? 0
    }
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
