import Foundation

public struct TimeSpan: Codable, Equatable, Hashable, Sendable {
    public var start: Double
    public var end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
    public var duration: Double { end - start }
}
public struct PointerSample: Codable, Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var y: Double
    public var clicked: Bool
    public init(time: Double, x: Double, y: Double, clicked: Bool) {
        self.time = time; self.x = x; self.y = y; self.clicked = clicked
    }
}
public struct ZoomSegment: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var start: Double
    public var end: Double
    public var centerX: Double
    public var centerY: Double
    public var scale: Double
    public var animationRange: TimeSpan? = nil
    public var manual: Bool
    public init(start: Double, end: Double, centerX: Double, centerY: Double, scale: Double = 1.8, manual: Bool = false) {
        self.start = start; self.end = end; self.centerX = centerX; self.centerY = centerY; self.scale = scale; self.manual = manual
    }
}
public struct Project: Codable, Equatable, Sendable {
    public static let maximumDuration = 7.0 * 24 * 60 * 60
    public var version = 1
    public var name = "未命名演示"
    public var duration: Double
    public var sourceRelativePath: String
    public var kept: [TimeSpan]
    public var zooms: [ZoomSegment] = []
    public var automaticZoomEnabled = true
    public init(duration: Double, sourceRelativePath: String) {
        self.duration = duration; self.sourceRelativePath = sourceRelativePath
        self.kept = duration > 0 ? [.init(start: 0, end: duration)] : []
    }
    public var timeline: EditTimeline { EditTimeline(kept: kept) }
    public func validate() throws {
        guard (1...2).contains(version) else { throw RecorderError.message("此工程版本暂不支持。") }
        guard duration.isFinite, duration > 0, duration <= Self.maximumDuration else { throw RecorderError.message("工程时长无效。") }
        let path = sourceRelativePath as NSString
        guard !path.isAbsolutePath, !path.pathComponents.contains(".."), path.pathComponents.first == "media", path.pathComponents.count >= 2 else {
            throw RecorderError.message("工程素材路径无效。")
        }
        var previous = 0.0
        for s in kept.sorted(by:{ $0.start < $1.start }) {
            guard s.start.isFinite, s.end.isFinite, s.start >= previous, s.end > s.start, s.end <= duration + 0.001 else { throw RecorderError.message("剪辑区间无效。") }
            previous = s.end
        }
        var previousZoomEnd = 0.0
        for z in zooms.sorted(by: { $0.start < $1.start }) {
            guard [z.start,z.end,z.centerX,z.centerY,z.scale].allSatisfy({ $0.isFinite }),
                  z.start >= previousZoomEnd, z.end > z.start, z.end <= duration + 0.001,
                  (0...1).contains(z.centerX), (0...1).contains(z.centerY), (1...3).contains(z.scale) else { throw RecorderError.message("聚焦区间无效或重叠。") }
            if let range = z.animationRange {
                guard range.start.isFinite, range.end.isFinite, range.start >= 0, range.end <= duration + 0.001, range.start <= z.start, range.end >= z.end, range.end > range.start else { throw RecorderError.message("聚焦动画范围无效。") }
            }
            previousZoomEnd = z.end
        }
    }
}
public enum RecorderError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
