import XCTest
import AVFoundation
import CoreImage
import ImageIO
@testable import RecorderMedia
import RecorderCore

final class MediaTests: XCTestCase {
    func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func fixture(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:320,AVVideoHeightKey:180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String:320,kCVPixelBufferHeightKey as String:180,kCVPixelBufferIOSurfacePropertiesKey as String: [:]])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        let context = CIContext()
        for frame in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)
            let color = frame < 60 ? CIColor(red:1,green:0,blue:0) : CIColor(red:0,green:0,blue:1)
            let base = CIImage(color:color).cropped(to:CGRect(x:0,y:0,width:320,height:180))
            let marker = CIImage(color:CIColor(red:0,green:1,blue:0)).cropped(to:CGRect(x:220,y:60,width:40,height:60))
            context.render(marker.composited(over:base),to:buffer!)
            XCTAssertTrue(adaptor.append(buffer!,withPresentationTime:CMTime(value:Int64(frame),timescale:30)))
        }
        input.markAsFinished(); await writer.finishWriting()
        XCTAssertEqual(writer.status,.completed)
    }
    func testExportsRealCutMP4AndGIF() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("source.mov")
        try await fixture(source)
        var p = Project(duration:4,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:0,end:1),.init(start:2,end:4)]
        p.zooms = [.init(start:2,end:4,centerX:0.75,centerY:0.5,scale:2,manual:true)]
        let movie = dir.appendingPathComponent("result.mp4")
        try await ExportService.export(project:p,samples:[],sourceURL:source,settings:.init(format:.mp4,longEdge:320,fps:30),destination:movie) { _ in }
        let asset = AVURLAsset(url:movie)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration,3,accuracy:1.0/30)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size,CGSize(width:320,height:180))
        let gen = AVAssetImageGenerator(asset:asset)
        gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
        let frame = try await gen.image(at:CMTime(seconds:1.7,preferredTimescale:600)).image
        let context = CIContext(); var pixel = [UInt8](repeating:0,count:4)
        context.render(CIImage(cgImage:frame),toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:160,y:90,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        XCTAssertGreaterThan(pixel[1],180,"Zoom must center the green marker after the cut")
        let gif = dir.appendingPathComponent("result.gif")
        try await ExportService.export(project:p,samples:[],sourceURL:source,settings:.init(format:.gif,longEdge:320,fps:10),destination:gif) { _ in }
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(gif as CFURL,nil))
        XCTAssertEqual(CGImageSourceGetCount(imageSource),30)
        let gifFrame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource,17,nil))
        context.render(CIImage(cgImage:gifFrame),toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:160,y:90,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
        XCTAssertGreaterThan(pixel[1],150,"GIF must use the same zoom as MP4")
        if let path = ProcessInfo.processInfo.environment["DEMO_QA_OUTPUT"] {
            let root = URL(fileURLWithPath:path)
            try FileManager.default.createDirectory(at:root.appendingPathComponent("media"),withIntermediateDirectories:true)
            let target = root.appendingPathComponent("media/original.mov")
            if !FileManager.default.fileExists(atPath:target.path) { try FileManager.default.copyItem(at:source,to:target) }
            p.name = "示例演示 · 聚焦与剪辑验证"
            try ProjectStore.save(p,samples:[],to:root)
        }
    }
    func testCancelledExportPreservesExistingDestination() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("source.mov"), dest = dir.appendingPathComponent("existing.mp4")
        try await fixture(source)
        let sentinel = Data("existing export".utf8); try sentinel.write(to:dest)
        let task = Task {
            try await ExportService.export(project:Project(duration:4,sourceRelativePath:"media/original.mov"),samples:[],sourceURL:source,settings:.init(format:.mp4,longEdge:320,fps:30),destination:dest) { _ in }
        }
        task.cancel()
        do { try await task.value; XCTFail("Cancellation must throw") } catch {}
        XCTAssertEqual(try Data(contentsOf:dest),sentinel)
    }
    func testProjectRoundTripAndMove() throws {
        let dir = try temporaryFolder(), root = dir.appendingPathComponent("demo.demorec")
        try FileManager.default.createDirectory(at:root.appendingPathComponent("media"),withIntermediateDirectories:true)
        try Data("fixture".utf8).write(to:root.appendingPathComponent("media/original.mov"))
        let p = Project(duration:4,sourceRelativePath:"media/original.mov")
        try ProjectStore.save(p,samples:[],to:root)
        let moved = dir.appendingPathComponent("moved.demorec")
        try FileManager.default.moveItem(at:root,to:moved)
        let loaded = try ProjectStore.open(moved)
        XCTAssertEqual(loaded.project,p)
        XCTAssertTrue(FileManager.default.fileExists(atPath:loaded.sourceURL.path))
    }
}

extension MediaTests {
    func testRecordingRetainsStaticTail() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("source.mov"), target = dir.appendingPathComponent("static.mov")
        try await fixture(source)
        let asset = AVURLAsset(url:source)
        let tracks = try await asset.loadTracks(withMediaType:.video)
        let reader = try AVAssetReader(asset:asset)
        let output = AVAssetReaderTrackOutput(track:tracks[0],outputSettings:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
        reader.add(output); XCTAssertTrue(reader.startReading())
        let sample = try XCTUnwrap(output.copyNextSampleBuffer())
        let sink = try FrameWriter(url:target,width:320,height:180,microphone:false)
        sink.queue.sync { sink.appendVideo(sample) }
        _ = try await sink.finish(at:CMTime(seconds:2,preferredTimescale:600))
        let duration = try await AVURLAsset(url:target).load(.duration).seconds
        XCTAssertEqual(duration,2+1.0/30,accuracy:1.0/30,"Stopping after an unchanged screen must retain the static interval")
    }
    func testRecoverIncompleteReadableRecording() async throws {
        let dir = try temporaryFolder()
        let root = try ProjectStore.createFolder(in:dir,name:"recovery")
        try await fixture(root.appendingPathComponent("media/original.mov"))
        let recovered = try await ProjectStore.recover(root)
        XCTAssertEqual(recovered.project.duration,4,accuracy:1.0/30)
        XCTAssertTrue(FileManager.default.fileExists(atPath:root.appendingPathComponent("project.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("recording.inprogress").path))
    }
}

extension MediaTests {
    func testAudioStaysAlignedAfterReorderAndCut() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("video.mov")
        try await fixture(source)
        let audioURL = dir.appendingPathComponent("pulses.caf")
        let format = AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let file = try AVAudioFile(forWriting:audioURL,settings:format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:192000)!
        buffer.frameLength = 192000
        for i in 0..<192000 {
            let t = Double(i)/48000
            let active = (0.5..<0.6).contains(t) || (2.5..<2.6).contains(t)
            buffer.floatChannelData![0][i] = active ? Float(sin(t*440*2*Double.pi)*0.8) : 0
        }
        try file.write(from:buffer)
        let videoAsset = AVURLAsset(url:source), audioAsset = AVURLAsset(url:audioURL)
        let videoTracks = try await videoAsset.loadTracks(withMediaType:.video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType:.audio)
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!
        let audio = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!
        let range = CMTimeRange(start:.zero,duration:CMTime(seconds:4,preferredTimescale:600))
        try video.insertTimeRange(range,of:videoTracks[0],at:.zero)
        try audio.insertTimeRange(range,of:audioTracks[0],at:.zero)
        let combined = dir.appendingPathComponent("combined.mov")
        let exporter = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
        try await exporter.export(to:combined,as:.mov)
        var p = Project(duration:4,sourceRelativePath:"media/original.mov")
        p.kept = [.init(start:2,end:4),.init(start:0,end:1)]
        let final = dir.appendingPathComponent("audio.mp4")
        try await ExportService.export(project:p,samples:[],sourceURL:combined,settings:.init(format:.mp4,longEdge:320),destination:final) { _ in }
        let asset = AVURLAsset(url:final)
        let tracks = try await asset.loadTracks(withMediaType:.audio)
        XCTAssertEqual(tracks.count,1)
        let reader = try AVAssetReader(asset:asset)
        let output = AVAssetReaderTrackOutput(track:try XCTUnwrap(tracks.first),outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVLinearPCMIsNonInterleaved:false,AVSampleRateKey:48000,AVNumberOfChannelsKey:1])
        reader.add(output); XCTAssertTrue(reader.startReading())
        var peaks: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = sample.dataBuffer else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            var values = [Float](repeating:0,count:bytes/4)
            _ = values.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:bytes,destination:$0.baseAddress!) }
            for (i,value) in values.enumerated() where abs(value) > 0.3 { peaks.append(sample.presentationTimeStamp.seconds+Double(i)/48000) }
        }
        XCTAssertEqual(try XCTUnwrap(peaks.first),0.5,accuracy:0.1)
        let second = try XCTUnwrap(peaks.first(where:{$0 > 1}))
        XCTAssertEqual(second,2.5,accuracy:0.1)
    }
}

extension MediaTests {
    func testExportRefusesSymlinkToOriginal() async throws {
        let dir = try temporaryFolder(), media = dir.appendingPathComponent("project/media")
        try FileManager.default.createDirectory(at:media,withIntermediateDirectories:true)
        let source = media.appendingPathComponent("original.mp4")
        let sentinel = Data("original unchanged".utf8); try sentinel.write(to:source)
        let alias = dir.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at:alias,withDestinationURL:media)
        XCTAssertThrowsError(try ExportService.validateDestination(alias.appendingPathComponent("original.mp4"),sourceURL:source,projectRoot:dir.appendingPathComponent("project")))
        XCTAssertEqual(try Data(contentsOf:source),sentinel)
    }
}

private final class ExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void,Error>?
    func install(_ task: Task<Void,Error>) { lock.lock(); self.task = task; lock.unlock() }
    func cancel() { lock.lock(); let running = task; lock.unlock(); running?.cancel() }
}
extension MediaTests {
    func testMidGIFCancellationRemovesTemporaryFilesAndPreservesDestination() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("source.mov"), destination = dir.appendingPathComponent("existing.gif")
        try await fixture(source)
        let sentinel = Data("keep me".utf8); try sentinel.write(to:destination)
        let cancellation = ExportCancellation()
        let task = Task {
            try await ExportService.export(project:Project(duration:4,sourceRelativePath:"media/original.mov"),samples:[],sourceURL:source,settings:.init(format:.gif,longEdge:320,fps:20),destination:destination) { value in
                if value > 0 { cancellation.cancel() }
            }
        }
        cancellation.install(task)
        do { try await task.value; XCTFail("Must cancel after beginning GIF rendering") } catch is CancellationError {} catch { XCTFail("Unexpected failure: \(error)") }
        XCTAssertEqual(try Data(contentsOf:destination),sentinel)
        let files = try FileManager.default.contentsOfDirectory(atPath:dir.path)
        XCTAssertFalse(files.contains(where:{$0.hasPrefix(".demo-export-")}))
    }
}

extension MediaTests {
    func testReorderedMP4AndGIFKeepFocusWithSourceClip() async throws {
        let dir = try temporaryFolder(), source = dir.appendingPathComponent("source.mov")
        try await fixture(source)
        var p = Project(duration:4,sourceRelativePath:"media/original.mov")
        p.version = 2
        p.kept = [.init(start:2,end:4),.init(start:0,end:1)]
        p.zooms = [.init(start:2,end:4,centerX:0.75,centerY:0.5,scale:2,manual:true)]
        let context = CIContext()
        for format in [ExportFormat.mp4,.gif] {
            let result = dir.appendingPathComponent("reordered.\(format.rawValue)")
            try await ExportService.export(project:p,samples:[],sourceURL:source,settings:.init(format:format,longEdge:320,fps:10),destination:result) { _ in }
            var frames: [CGImage] = []
            if format == .mp4 {
                let asset = AVURLAsset(url:result)
                let duration = try await asset.load(.duration).seconds
                XCTAssertEqual(duration,3,accuracy:1.0/30)
                let generator = AVAssetImageGenerator(asset:asset)
                generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
                frames.append(try await generator.image(at:CMTime(seconds:0.7,preferredTimescale:600)).image)
                frames.append(try await generator.image(at:CMTime(seconds:2.5,preferredTimescale:600)).image)
            } else {
                let gif = try XCTUnwrap(CGImageSourceCreateWithURL(result as CFURL,nil))
                XCTAssertEqual(CGImageSourceGetCount(gif),30)
                frames.append(try XCTUnwrap(CGImageSourceCreateImageAtIndex(gif,7,nil)))
                frames.append(try XCTUnwrap(CGImageSourceCreateImageAtIndex(gif,25,nil)))
            }
            var pixel = [UInt8](repeating:0,count:4)
            context.render(CIImage(cgImage:frames[0]),toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:160,y:90,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
            XCTAssertGreaterThan(pixel[1],150,"Moved clip must retain its zoom")
            context.render(CIImage(cgImage:frames[1]),toBitmap:&pixel,rowBytes:4,bounds:CGRect(x:160,y:90,width:1,height:1),format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())
            XCTAssertGreaterThan(pixel[0],150,"Original first clip must now appear last")
            XCTAssertLessThan(pixel[1],80)
        }
    }
}
