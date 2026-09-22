import Foundation
public struct CameraState: Equatable, Sendable {
    public var centerX: Double
    public var centerY: Double
    public var scale: Double
    public init(centerX: Double = 0.5, centerY: Double = 0.5, scale: Double = 1) {
        self.centerX = centerX; self.centerY = centerY; self.scale = scale
    }
}
public enum AutoZoomPlanner {
    public static func plan(samples: [PointerSample], duration: Double) -> [ZoomSegment] {
        let clicks = samples.filter { $0.clicked && $0.time >= 0 && $0.time < duration && (0...1).contains($0.x) && (0...1).contains($0.y) }.sorted { $0.time < $1.time }
        var groups: [[PointerSample]] = []
        for click in clicks {
            if let last = groups.last?.last, click.time-last.time <= 1.5 { groups[groups.count-1].append(click) }
            else { groups.append([click]) }
        }
        var result: [ZoomSegment] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let start = max(0,first.time-0.25), end = min(duration,last.time+1.65)
            if let previous = result.last, start < previous.end {
                result[result.count-1].end = end
            } else {
                result.append(.init(start:start,end:end,centerX:first.x,centerY:first.y))
            }
        }
        return result
    }
}
public enum CameraEvaluator {
    private static func smooth(_ t: Double) -> Double { let u = min(1,max(0,t)); return u*u*(3-2*u) }
    public static func evaluate(time: Double, segments: [ZoomSegment], samples: [PointerSample]) -> CameraState {
        guard let z = segments.first(where: { time >= $0.start && time < $0.end }) else { return CameraState() }
        let length = z.end-z.start
        let enter = min(0.35,length/2), leave = min(0.45,length/2)
        let amount = min(smooth((time-z.start)/enter),smooth((z.end-time)/leave))
        let scale = 1 + (z.scale-1)*amount
        var x = z.centerX, y = z.centerY
        if !z.manual {
            // Event-domain deterministic follow: independent of render order and frame rate.
            var previous = z.start
            for s in samples where s.time >= z.start && s.time <= time && s.time < z.end {
                let dt = max(0,s.time-previous), limit = 0.3/z.scale
                let targetX = s.x > x+limit ? s.x-limit : (s.x < x-limit ? s.x+limit : x)
                let targetY = s.y > y+limit ? s.y-limit : (s.y < y-limit ? s.y+limit : y)
                let alpha = 1-exp(-dt/0.16)
                x += (targetX-x)*alpha; y += (targetY-y)*alpha; previous = s.time
            }
        }
        let half = 0.5/scale
        return .init(centerX:min(1-half,max(half,0.5+(x-0.5)*amount)), centerY:min(1-half,max(half,0.5+(y-0.5)*amount)), scale:scale)
    }
}

/// Precomputes follow positions once; rendering never scans an entire recording per frame.
public struct CameraTrack: Sendable {
    private struct Key: Sendable { var time: Double; var x: Double; var y: Double }
    private var segments: [ZoomSegment]
    private var tracks: [[Key]]
    public init(segments: [ZoomSegment], samples: [PointerSample]) {
        self.segments = segments.sorted { $0.start < $1.start }
        let ordered = samples.sorted { $0.time < $1.time }
        var index = 0
        self.tracks = self.segments.map { z in
            var keys = [Key(time:z.start,x:z.centerX,y:z.centerY)]
            var x = z.centerX, y = z.centerY, last = z.start
            while index < ordered.count && ordered[index].time < z.start { index += 1 }
            while index < ordered.count && ordered[index].time < z.end {
                let s = ordered[index]; index += 1
                let limit = 0.3/z.scale, a = 1-exp(-max(0,s.time-last)/0.16)
                let tx = s.x > x+limit ? s.x-limit : (s.x < x-limit ? s.x+limit : x)
                let ty = s.y > y+limit ? s.y-limit : (s.y < y-limit ? s.y+limit : y)
                x += (tx-x)*a; y += (ty-y)*a; last = s.time
                keys.append(Key(time:s.time,x:x,y:y))
            }
            return keys
        }
    }
    public func evaluate(time: Double) -> CameraState {
        var lo = 0, hi = segments.count
        while lo < hi { let mid = (lo+hi)/2; if segments[mid].start <= time { lo = mid+1 } else { hi = mid } }
        let i = lo-1
        guard i >= 0, time < segments[i].end else { return CameraState() }
        var z = segments[i]
        if !z.manual {
            let keys = tracks[i]; lo = 0; hi = keys.count
            while lo < hi { let mid = (lo+hi)/2; if keys[mid].time <= time { lo = mid+1 } else { hi = mid } }
            let a = keys[max(0,lo-1)], b = keys[min(keys.count-1,lo)]
            let u = b.time > a.time ? min(1,max(0,(time-a.time)/(b.time-a.time))) : 0
            z.centerX = a.x+(b.x-a.x)*u; z.centerY = a.y+(b.y-a.y)*u; z.manual = true
        }
        return CameraEvaluator.evaluate(time:time,segments:[z],samples:[])
    }
}
