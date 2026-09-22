import Foundation
import AVFoundation
import CoreImage
import RecorderCore

public struct RenderedMedia {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let duration: Double
    public let size: CGSize
}
public enum MediaRenderer {
    public static func makeComposition(project: Project, samples: [PointerSample], sourceURL: URL, longEdge: Int = 0, fps: Int = 30) async throws -> RenderedMedia {
        try project.validate()
        guard project.timeline.duration > 0 else { throw RecorderError.message("请保留至少一段视频后再导出。") }
        let asset = AVURLAsset(url:sourceURL)
        guard let sourceVideo = try await asset.loadTracks(withMediaType:.video).first else { throw RecorderError.message("素材中没有可读取的视频。") }
        let actualDuration = try await asset.load(.duration).seconds
        guard actualDuration.isFinite, project.kept.allSatisfy({ $0.end <= actualDuration + 1.0/30 }) else { throw RecorderError.message("工程剪辑区间超出了实际视频时长。") }
        let natural = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let transformed = CGRect(origin:.zero,size:natural).applying(transform)
        let width = abs(transformed.width), height = abs(transformed.height)
        let factor = longEdge > 0 ? min(1,Double(longEdge)/max(width,height)) : 1
        let size = CGSize(width:max(2,floor(width*factor/2)*2),height:max(2,floor(height*factor/2)*2))
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else { throw RecorderError.message("无法创建视频轨道。") }
        video.preferredTransform = transform
        let sourceAudio = try await asset.loadTracks(withMediaType:.audio)
        let audio = sourceAudio.map { _ in composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)! }
        let parameters = audio.map { AVMutableAudioMixInputParameters(track:$0) }
        var cursor = CMTime.zero
        for span in project.kept {
            let range = CMTimeRange(start:CMTime(seconds:span.start,preferredTimescale:60000),duration:CMTime(seconds:span.duration,preferredTimescale:60000))
            try video.insertTimeRange(range,of:sourceVideo,at:cursor)
            for (i,track) in sourceAudio.enumerated() {
                let available = try await track.load(.timeRange)
                let intersection = CMTimeRangeGetIntersection(range,otherRange:available)
                if intersection.duration.seconds > 0 {
                    let insertion = cursor + intersection.start - range.start
                    try audio[i].insertTimeRange(intersection,of:track,at:insertion)
                    let fade = CMTime(seconds:min(0.005,intersection.duration.seconds/2),preferredTimescale:60000)
                    parameters[i].setVolumeRamp(fromStartVolume:0,toEndVolume:1,timeRange:CMTimeRange(start:insertion,duration:fade))
                    parameters[i].setVolumeRamp(fromStartVolume:1,toEndVolume:0,timeRange:CMTimeRange(start:insertion+intersection.duration-fade,duration:fade))
                }
            }
            cursor = cursor + range.duration
        }
        let timeline = project.timeline
        let zooms = project.zooms.filter { $0.manual || project.automaticZoomEnabled }
        let cameraTrack = CameraTrack(segments:zooms,samples:samples)
        let context = CIContext(options:[.cacheIntermediates:false])
        let vc = try await AVMutableVideoComposition.videoComposition(with:composition, applyingCIFiltersWithHandler: { request in
            let outputTime = min(max(0,request.compositionTime.seconds),max(0,timeline.duration-0.000001))
            let sourceTime = timeline.sourceTime(at:outputTime) ?? 0
            let camera = cameraTrack.evaluate(time:sourceTime)
            let image = request.sourceImage
            let extent = image.extent
            let crop = CGRect(x:extent.minX+(camera.centerX-0.5/camera.scale)*extent.width,
                              y:extent.minY+(1-camera.centerY-0.5/camera.scale)*extent.height,
                              width:extent.width/camera.scale,height:extent.height/camera.scale)
            let output = image.cropped(to:crop).transformed(by:CGAffineTransform(translationX:-crop.minX,y:-crop.minY)).transformed(by:CGAffineTransform(scaleX:size.width/crop.width,y:size.height/crop.height)).cropped(to:CGRect(origin:.zero,size:size))
            request.finish(with:output,context:context)
        })
        vc.renderSize = size
        vc.frameDuration = CMTime(value:1,timescale:Int32(fps))
        let mix = AVMutableAudioMix(); mix.inputParameters = parameters
        return .init(composition:composition,videoComposition:vc,audioMix:mix,duration:timeline.duration,size:size)
    }
}
