import Foundation
import AVFoundation
import RecorderCore

public struct OpenedProject {
    public var project: Project
    public var samples: [PointerSample]
    public var sourceURL: URL
    public var root: URL
}
public enum ProjectStore {
    public static func save(_ project: Project, samples: [PointerSample], to root: URL) throws {
        try project.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(samples).write(to:root.appendingPathComponent("events.json"),options:.atomic)
        try encoder.encode(project).write(to:root.appendingPathComponent("project.json"),options:.atomic)
    }
    public static func open(_ root: URL) throws -> OpenedProject {
        let decoder = JSONDecoder()
        let p = try decoder.decode(Project.self,from:Data(contentsOf:root.appendingPathComponent("project.json")))
        try p.validate()
        let source = root.appendingPathComponent(p.sourceRelativePath).resolvingSymlinksInPath()
        let canonical = root.resolvingSymlinksInPath().path + "/"
        guard source.path.hasPrefix(canonical), FileManager.default.fileExists(atPath:source.path) else { throw RecorderError.message("工程原始素材缺失或位于工程外。") }
        let eventURL = root.appendingPathComponent("events.json")
        let samples = FileManager.default.fileExists(atPath:eventURL.path) ? try decoder.decode([PointerSample].self,from:Data(contentsOf:eventURL)) : []
        guard samples.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time <= p.duration+0.1 && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { throw RecorderError.message("鼠标轨迹数据无效。") }
        return .init(project:p,samples:samples.sorted{$0.time < $1.time},sourceURL:source,root:root)
    }
    public static func recover(_ root: URL) async throws -> OpenedProject {
        let url = root.appendingPathComponent("media/original.mov")
        let asset = AVURLAsset(url:url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, !(try await asset.loadTracks(withMediaType:.video)).isEmpty else { throw RecorderError.message("此录制尚未形成可恢复的视频。原始文件仍已保留。") }
        var project = Project(duration:duration,sourceRelativePath:"media/original.mov")
        project.name = "恢复的录制"
        try save(project,samples:[],to:root)
        try? FileManager.default.removeItem(at:root.appendingPathComponent("recording.inprogress"))
        return try open(root)
    }
    public static func createFolder(in parent: URL, name: String) throws -> URL {
        let root = parent.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6)).demorec")
        try FileManager.default.createDirectory(at:root.appendingPathComponent("media"),withIntermediateDirectories:true)
        try Data().write(to:root.appendingPathComponent("recording.inprogress"))
        return root
    }
}
