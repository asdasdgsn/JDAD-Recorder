import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import RecorderCore

public enum ExportFormat: String, CaseIterable, Sendable { case mp4, gif }
public struct ExportSettings: Sendable {
    public var format: ExportFormat
    public var longEdge: Int
    public var fps: Int
    public init(format: ExportFormat = .mp4,longEdge: Int = 1920,fps: Int = 30) {
        self.format = format; self.longEdge = longEdge; self.fps = fps
    }
}
public enum ExportService {
    public static func export(project: Project, samples: [PointerSample], sourceURL: URL, settings: ExportSettings, destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        try Task.checkCancellation()
        guard settings.fps > 0, settings.fps <= 60, settings.longEdge >= 0 else { throw RecorderError.message("导出参数无效。") }
        let rendered = try await MediaRenderer.makeComposition(project:project,samples:samples,sourceURL:sourceURL,longEdge:settings.longEdge,fps:settings.format == .gif ? settings.fps : 30)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".demo-export-\(UUID().uuidString).\(settings.format.rawValue)")
        defer { try? FileManager.default.removeItem(at:temporary) }
        switch settings.format {
        case .mp4:
            guard let session = AVAssetExportSession(asset:rendered.composition,presetName:AVAssetExportPresetHighestQuality) else { throw RecorderError.message("无法启动视频导出。") }
            session.videoComposition = rendered.videoComposition; session.audioMix = rendered.audioMix
            session.shouldOptimizeForNetworkUse = true
            let monitor = Task {
                while !Task.isCancelled { progress(Double(session.progress)); try? await Task.sleep(nanoseconds:100_000_000) }
            }
            defer { monitor.cancel() }
            try await withTaskCancellationHandler {
                try await session.export(to:temporary,as:.mp4)
            } onCancel: { session.cancelExport() }
        case .gif:
            let generator = AVAssetImageGenerator(asset:rendered.composition)
            generator.videoComposition = rendered.videoComposition
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let count = max(1,Int(ceil(rendered.duration*Double(settings.fps))))
            guard let output = CGImageDestinationCreateWithURL(temporary as CFURL,UTType.gif.identifier as CFString,count,nil) else { throw RecorderError.message("无法创建 GIF 文件。") }
            CGImageDestinationSetProperties(output,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
            for index in 0..<count {
                try Task.checkCancellation()
                let time = CMTime(seconds:Double(index)/Double(settings.fps),preferredTimescale:60000)
                let image = try await generator.image(at:time).image
                autoreleasepool {
                    CGImageDestinationAddImage(output,image,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:1.0/Double(settings.fps),kCGImagePropertyGIFUnclampedDelayTime:1.0/Double(settings.fps)]] as CFDictionary)
                }
                progress(Double(index+1)/Double(count))
            }
            guard CGImageDestinationFinalize(output) else { throw RecorderError.message("GIF 写入失败，请检查磁盘空间。") }
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath:destination.path) { _ = try FileManager.default.replaceItemAt(destination,withItemAt:temporary) }
        else { try FileManager.default.moveItem(at:temporary,to:destination) }
        progress(1)
    }
}
