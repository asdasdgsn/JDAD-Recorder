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
