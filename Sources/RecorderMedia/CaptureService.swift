import AppKit
import AVFoundation
import ScreenCaptureKit
import RecorderCore

public struct CaptureSource: Identifiable {
    public let id: String
    public let title: String
    public let display: SCDisplay?
    public let window: SCWindow?
    public var isWindow: Bool { window != nil }
}
public struct CapturedRecording {
    public let url: URL
    public let duration: Double
    public let samples: [PointerSample]
}

/// All writer mutation is confined to queue; main-actor consumers use snapshot methods.
final class FrameWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label:"demo.capture.writer",qos:.userInitiated)
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput?
    private var firstPTS: CMTime?
    private var lastPTS: CMTime?
    private var lastFrame: CMSampleBuffer?
    private var closed = false
    private var failure: Error?
    private var currentRect: CGRect?
    private var destinationRect: CGRect?
    private let outputSize: CGSize
    var onFailure: (@Sendable (Error) -> Void)?
    init(url: URL,width: Int,height: Int,microphone: Bool) throws {
        outputSize = CGSize(width:width,height:height)
        writer = try AVAssetWriter(outputURL:url,fileType:.mov)
        video = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:max(3_000_000,width*height*5),AVVideoExpectedSourceFrameRateKey:30,AVVideoMaxKeyFrameIntervalKey:60]])
        video.expectsMediaDataInRealTime = true
        audio = microphone ? AVAssetWriterInput(mediaType:.audio,outputSettings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:128000]) : nil
        super.init()
        writer.add(video)
        if let audio { audio.expectsMediaDataInRealTime = true; writer.add(audio) }
    }
    func stream(_ stream: SCStream,didOutputSampleBuffer sampleBuffer: CMSampleBuffer,of type: SCStreamOutputType) {
        guard !closed, sampleBuffer.isValid else { return }
        let pts = sampleBuffer.presentationTimeStamp
        guard pts.isNumeric else { return }
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue else { return }
            if let value = attachments.first?[.screenRect] as? NSValue { currentRect = value.rectValue }
            else if let dict = attachments.first?[.screenRect] as? [String:Any] { currentRect = CGRect(dictionaryRepresentation:dict as CFDictionary) }
            if let value = attachments.first?[.contentRect] as? NSValue { destinationRect = value.rectValue }
            else if let dict = attachments.first?[.contentRect] as? [String:Any] { destinationRect = CGRect(dictionaryRepresentation:dict as CFDictionary) }
            appendVideo(sampleBuffer)
        } else if type == .microphone, let firstPTS, pts >= firstPTS, let audio, audio.isReadyForMoreMediaData {
            if !audio.append(sampleBuffer) { fail(writer.error ?? RecorderError.message("麦克风写入失败。")) }
        }
    }
    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !closed else { return }
        let pts = sampleBuffer.presentationTimeStamp
        if firstPTS == nil {
            guard writer.startWriting() else { fail(writer.error ?? RecorderError.message("录制写入无法启动。")); return }
            writer.startSession(atSourceTime:pts); firstPTS = pts
        }
        if video.isReadyForMoreMediaData {
            if !video.append(sampleBuffer) { fail(writer.error ?? RecorderError.message("视频写入失败。")) }
            else { lastPTS = pts; lastFrame = sampleBuffer }
        }
    }
    private func fail(_ error: Error) { guard failure == nil else { return }; failure = error; onFailure?(error) }
    func stream(_ stream: SCStream,didStopWithError error: Error) { onFailure?(error) }
    func mapPoint(_ point: CGPoint, fallback: CGRect, windowFrame: CGRect?) -> CGPoint? {
        queue.sync {
            guard firstPTS != nil else { return nil }
            let rect = currentRect ?? fallback
            // Reject transient geometry while a moved/resized window is awaiting its next frame.
            if let actual = windowFrame, abs(actual.minX-rect.minX) > 2 || abs(actual.minY-rect.minY) > 2 || abs(actual.width-rect.width) > 2 || abs(actual.height-rect.height) > 2 { return nil }
            guard let destinationRect else { return nil }
            return PointerMapping.normalize(point:point,contentRect:rect,destinationRect:destinationRect,canvasSize:outputSize)
        }
    }
    func finish(at stopTime: CMTime) async throws -> (Double,Double) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.closed else { continuation.resume(throwing:RecorderError.message("录制已结束。")); return }
                self.closed = true
                guard let first = self.firstPTS, let last = self.lastPTS else {
                    self.writer.cancelWriting(); continuation.resume(throwing:RecorderError.message("未收到视频画面，请检查录屏权限后重试。")); return
                }
                var end = last
                if stopTime > last, let frame = self.lastFrame, self.video.isReadyForMoreMediaData {
                    var timing = CMSampleTimingInfo(duration:CMTime(value:1,timescale:30),presentationTimeStamp:stopTime,decodeTimeStamp:.invalid)
                    var tail: CMSampleBuffer?
                    if CMSampleBufferCreateCopyWithNewTiming(allocator:kCFAllocatorDefault,sampleBuffer:frame,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleBufferOut:&tail) == noErr, let tail, self.video.append(tail) { end = stopTime }
                }
                let finalDuration = end.seconds-first.seconds+1.0/30
                self.lastFrame = nil
                self.writer.endSession(atSourceTime:end+CMTime(value:1,timescale:30))
                self.video.markAsFinished(); self.audio?.markAsFinished()
                self.writer.finishWriting {
                    if self.writer.status == .completed { continuation.resume(returning:(first.seconds,finalDuration)) }
                    else { continuation.resume(throwing:self.writer.error ?? self.failure ?? RecorderError.message("录制文件未能完成写入。")) }
                }
            }
        }
    }
    func cancel() { queue.async { self.closed = true; self.writer.cancelWriting() } }
}

@MainActor
public final class CaptureService {
    private var stream: SCStream?
    private var sink: FrameWriter?
    private var url: URL?
    private let pointer = PointerRecorder()
    private var ownApplications: [SCRunningApplication] = []
    public var onUnexpectedStop: ((Error) -> Void)?
    public init() {}
    public func sources() async throws -> [CaptureSource] {
        let content = try await SCShareableContent.excludingDesktopWindows(true,onScreenWindowsOnly:true)
        ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let displays = content.displays.enumerated().map { i,d in CaptureSource(id:"display-\(d.displayID)",title:"显示器 \(i+1) · \(d.width) × \(d.height)",display:d,window:nil) }
        let windows = content.windows.filter { $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 80 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }.sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }.map { w in CaptureSource(id:"window-\(w.windowID)",title:"\(w.owningApplication?.applicationName ?? "窗口") — \(w.title ?? "未命名")",display:nil,window:w) }
        return displays+windows
    }
    public static var microphones: [AVCaptureDevice] { AVCaptureDevice.DiscoverySession(deviceTypes:[.microphone,.external],mediaType:.audio,position:.unspecified).devices }
    public func start(source: CaptureSource,microphone: Bool,deviceID: String?,destination: URL) async throws {
        guard stream == nil else { throw RecorderError.message("已有正在进行的录制。") }
        if microphone {
            let allowed = await AVCaptureDevice.requestAccess(for:.audio)
            guard allowed else { throw RecorderError.message("麦克风未授权。请在系统设置中开启，或关闭麦克风后录制。") }
        }
        let filter: SCContentFilter
        if let window = source.window { filter = SCContentFilter(desktopIndependentWindow:window) }
        else if let display = source.display { filter = SCContentFilter(display:display,excludingApplications:ownApplications,exceptingWindows:[]) }
        else { throw RecorderError.message("请选择录制来源。") }
        let config = SCStreamConfiguration()
        let rect = filter.contentRect
        let scale = Double(filter.pointPixelScale)
        let reduction = min(1,3840/max(rect.width*scale,rect.height*scale))
        config.width = max(2,Int(rect.width*scale*reduction)/2*2); config.height = max(2,Int(rect.height*scale*reduction)/2*2)
        config.minimumFrameInterval = CMTime(value:1,timescale:30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5; config.showsCursor = true; config.capturesAudio = false
        config.captureMicrophone = microphone; config.microphoneCaptureDeviceID = deviceID
        config.scalesToFit = true; config.ignoreShadowsSingleWindow = true
        let writer = try FrameWriter(url:destination,width:config.width,height:config.height,microphone:microphone)
        writer.onFailure = { [weak self] error in Task { @MainActor in self?.onUnexpectedStop?(error) } }
        let stream = SCStream(filter:filter,configuration:config,delegate:writer)
        try stream.addStreamOutput(writer,type:.screen,sampleHandlerQueue:writer.queue)
        if microphone { try stream.addStreamOutput(writer,type:.microphone,sampleHandlerQueue:writer.queue) }
        self.stream = stream; self.sink = writer; self.url = destination
        let sourceRect = source.window?.frame ?? source.display?.frame ?? rect
        pointer.start { [weak writer] point in
            var actual: CGRect?
            if let window = source.window {
                guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow],window.windowID) as? [[String:Any]],let info = list.first,let bounds = info[kCGWindowBounds as String] as? [String:Any] else { return nil }
                actual = CGRect(dictionaryRepresentation:bounds as CFDictionary)
            }
            return writer?.mapPoint(point,fallback:sourceRect,windowFrame:actual)
        }
        do { try await stream.startCapture() }
        catch { pointer.stopMonitoring(); writer.cancel(); self.stream = nil; self.sink = nil; self.url = nil; throw error }
    }
    public func stop() async throws -> CapturedRecording {
        guard let stream, let sink, let url else { throw RecorderError.message("当前没有录制。") }
        self.stream = nil
        defer { pointer.stopMonitoring(); self.sink = nil; self.url = nil }
        let stoppedAt = CMClockGetTime(CMClockGetHostTimeClock())
        try? await stream.stopCapture()
        let (anchor,duration) = try await sink.finish(at:stoppedAt)
        return .init(url:url,duration:duration,samples:pointer.stop(anchor:anchor,duration:duration))
    }
}
