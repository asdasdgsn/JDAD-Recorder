import Foundation

public struct SnapResult: Equatable {
    public let time: Double
    public let target: Double?
}
public enum TimelineSnap {
    public static func resolve(_ time: Double,targets: [Double],tolerance: Double,range: ClosedRange<Double>) -> SnapResult {
        let bounded = min(range.upperBound,max(range.lowerBound,time.isFinite ? time : range.lowerBound))
        if let target = targets.filter({ $0.isFinite && range.contains($0) && abs($0-bounded) <= max(0,tolerance) }).min(by:{abs($0-bounded) < abs($1-bounded)}) {
            return .init(time:target,target:target)
        }
        return .init(time:min(range.upperBound,max(range.lowerBound,(bounded*30).rounded()/30)),target:nil)
    }
}
public enum ZoomEdge { case start, end }

extension Project {
    /// Edits only the projection of a source-time effect in the chosen clip. Other visible
    /// pieces retain their original animation envelope, so their image does not jump.
    public func resizingZoom(_ id: UUID,inClip index: Int,edge: ZoomEdge,toOutputTime outputTime: Double) -> Project {
        guard kept.indices.contains(index), outputTime.isFinite, let z = zooms.first(where:{$0.id == id}) else { return self }
        let clip = kept[index], offset = timeline.boundaries[index]
        let visibleStart = max(z.start,clip.start), visibleEnd = min(z.end,clip.end)
        guard visibleEnd > visibleStart else { return self }
        let other = zooms.filter { $0.id != id }
        let left = max(clip.start,other.filter{$0.end <= visibleStart}.map(\.end).max() ?? clip.start)
        let right = min(clip.end,other.filter{$0.start >= visibleEnd}.map(\.start).min() ?? clip.end)
        let minimum = min(1.0/30,visibleEnd-visibleStart)
        let sourceTime = clip.start + outputTime-offset
        var edited = z
        edited.start = visibleStart; edited.end = visibleEnd; edited.animationRange = nil
        switch edge {
        case .start: edited.start = max(left,min(visibleEnd-minimum,sourceTime))
        case .end: edited.end = min(right,max(visibleStart+minimum,sourceTime))
        }
        // Do not create an undo entry or fragment effects for a click without movement.
        if edited.start == visibleStart && edited.end == visibleEnd { return self }
        let envelope = z.animationRange ?? TimeSpan(start:z.start,end:z.end)
        var fragments: [ZoomSegment] = [edited]
        if z.start < visibleStart {
            var before = z; before.id = UUID(); before.end = visibleStart; before.animationRange = envelope; fragments.append(before)
        }
        if z.end > visibleEnd {
            var after = z; after.id = UUID(); after.start = visibleEnd; after.animationRange = envelope; fragments.append(after)
        }
        var result = self
        result.version = 2
        result.zooms = (other+fragments).sorted{$0.start < $1.start}
        return result
    }
}
