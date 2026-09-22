import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers
import RecorderCore
import RecorderMedia

enum WorkspacePage: String { case library, capture, editor }
@MainActor
final class AppModel: ObservableObject {
    @Published var page: WorkspacePage = .library
    @Published var sources: [CaptureSource] = []
    @Published var sourceID = ""
    @Published var microphone = false
    @Published var microphoneID = ""
    @Published var busy = false {
        didSet { guard oldValue != busy else { return }; if busy { busyToken = work.begin() } else if let token = busyToken { work.end(token); busyToken = nil } }
    }
    @Published var recording = false
    @Published var countdown: Int?
    @Published var recordingStarted: Date?
    @Published var error: String?
    @Published var notice: String?
    @Published var project: Project?
    @Published var root: URL?
    @Published var position = 0.0
    @Published var selectionStart = 0.0
    @Published var selectionEnd = 0.0
    @Published var selectedZoom: UUID?
    @Published var selectedClip: Int?
    @Published var snapping = true
    @Published var timelineInteracting = false
    @Published var history = EditHistory()
    @Published var exportProgress = 0.0
    @Published var exporting = false {
        didSet { guard oldValue != exporting else { return }; if exporting { exportToken = work.begin() } else if let token = exportToken { work.end(token); exportToken = nil } }
    }
    @Published var showExport = false
    @Published var recent: [URL] = []
    @Published var thumbnails: [NSImage] = []
    @Published var renderReady = false
    private let work = CompletionGate()
    private var busyToken: UUID?
    private var exportToken: UUID?
    private var quitting = false
    private var pendingCaptureError: String?
    let player = AVPlayer()
    let capture = CaptureService()
    private var samples: [PointerSample] = []
    private var sourceURL: URL?
    private var observer: Any?
    private var renderTask: Task<Void,Never>?
    private var exportTask: Task<Void,Never>?
    private var renderGeneration = UUID()
    private var activeRecordingRoot: URL?
    init() {
        recent = (UserDefaults.standard.stringArray(forKey:"recentProjects") ?? []).map { URL(fileURLWithPath:$0) }.filter { FileManager.default.fileExists(atPath:$0.path) }
        observer = player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.05,preferredTimescale:600),queue:.main) { [weak self] time in
            MainActor.assumeIsolated { guard time.seconds.isFinite else { return }; self?.position = time.seconds }
        }
        if let parent = try? projectParent(), let folders = try? FileManager.default.contentsOfDirectory(at:parent,includingPropertiesForKeys:nil) {
            for folder in folders where folder.pathExtension == "demorec" && FileManager.default.fileExists(atPath:folder.appendingPathComponent("recording.inprogress").path) {
                if !recent.contains(folder) { recent.insert(folder,at:0) }
            }
        }
        capture.onUnexpectedStop = { [weak self] error in
            guard let self else { return }
            self.pendingCaptureError = error.localizedDescription
            guard self.recording, !self.busy else { return }
            self.notice = "录制来源已停止，正在保存已有内容。\(error.localizedDescription)"
            Task { await self.stopRecording() }
        }
    }
    var duration: Double { project?.timeline.duration ?? 0 }
    var canEdit: Bool { project != nil && !busy && !exporting && !recording && !quitting }
    var canExport: Bool { canEdit && !timelineInteracting && renderReady && duration > 0 }
    var microphones: [AVCaptureDevice] { CaptureService.microphones }
    func refreshSources() async {
        guard !busy && !recording else { return }
        busy = true; defer { busy = false }
        do {
            sources = try await capture.sources()
            if !sources.contains(where:{$0.id == sourceID}) { sourceID = sources.first?.id ?? "" }
        } catch { self.error = "无法读取屏幕和窗口：\(error.localizedDescription)\n请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Demo Recorder。" }
    }
    func newRecording() { guard !recording && !busy && !exporting && !quitting else { return }; player.pause(); page = .capture; Task { await refreshSources() } }
    private func projectParent() throws -> URL {
        let movies = FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first!
        let folder = movies.appendingPathComponent("Demo Recorder",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        return folder
    }
    func startRecording() async {
        guard !busy, !recording, !quitting, let source = sources.first(where:{$0.id == sourceID}) else { return }
        busy = true; pendingCaptureError = nil
        do {
            let name = Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second()).replacingOccurrences(of:"/",with:"-").replacingOccurrences(of:":",with:"-")
            let folder = try ProjectStore.createFolder(in:projectParent(),name:name)
            activeRecordingRoot = folder
            for value in (1...3).reversed() { countdown = value; try await Task.sleep(nanoseconds:1_000_000_000) }
            countdown = nil
            try await capture.start(source:source,microphone:microphone,deviceID:microphoneID.isEmpty ? nil : microphoneID,destination:folder.appendingPathComponent("media/original.mov"))
            recording = true; recordingStarted = Date(); busy = false
            if let pendingCaptureError { notice = "录制启动遇到问题：\(pendingCaptureError)"; await stopRecording() }
        } catch { countdown = nil; busy = false; self.error = error.localizedDescription }
    }
    func stopRecording() async {
        guard recording, !busy else { return }; busy = true
        do {
            let result = try await capture.stop()
            guard let folder = activeRecordingRoot else { throw RecorderError.message("工程目录丢失。") }
            var p = Project(duration:result.duration,sourceRelativePath:"media/original.mov")
            p.name = "功能演示 · \(Date().formatted(date:.abbreviated,time:.shortened))"
            p.zooms = AutoZoomPlanner.plan(samples:result.samples,duration:result.duration)
            try ProjectStore.save(p,samples:result.samples,to:folder)
            try? FileManager.default.removeItem(at:folder.appendingPathComponent("recording.inprogress"))
            if !result.samples.contains(where:{$0.clicked}) { notice = "本次没有采集到点击，已保留原始画面。你可以手动添加聚焦；若确实点击过，请检查系统权限。" }
            recording = false; busy = false; recordingStarted = nil; activeRecordingRoot = nil
            try load(folder)
        } catch { recording = false; busy = false; recordingStarted = nil; self.error = "保存录制失败：\(error.localizedDescription)\n已写入的素材保留在影片文件夹，可尝试导入恢复。" }
    }
    func openPanel() {
        guard !recording && !busy && !exporting && !quitting else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.message = "选择 .demorec 工程，或导入 MP4 / MOV 视频"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    func open(_ url: URL) {
        guard !recording && !busy && !exporting && !quitting else { return }
        if url.pathExtension == "demorec" {
            if !FileManager.default.fileExists(atPath:url.appendingPathComponent("project.json").path) {
                busy = true
                Task { defer { busy = false }; do { _ = try await ProjectStore.recover(url); try load(url); notice = "已恢复可读取的视频；未完成保存的鼠标轨迹无法恢复，可手动添加聚焦。" } catch { self.error = error.localizedDescription } }
            } else { do { try load(url) } catch { self.error = error.localizedDescription } }
        }
        else { Task { await importVideo(url) } }
    }
    func load(_ url: URL) throws {
        let opened = try ProjectStore.open(url)
        player.pause(); project = opened.project; samples = opened.samples; root = opened.root; sourceURL = opened.sourceURL
        history = EditHistory(); selectedZoom = nil; selectedClip = nil; position = 0; selectionStart = 0; selectionEnd = duration
        page = .editor; remember(url); rebuild()
    }
    private func importVideo(_ url: URL) async {
        busy = true; defer { busy = false }
        do {
            let asset = AVURLAsset(url:url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, !(try await asset.loadTracks(withMediaType:.video)).isEmpty else { throw RecorderError.message("请选择有效的视频文件。") }
            let folder = try ProjectStore.createFolder(in:projectParent(),name:"导入")
            let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
            let relative = "media/original.\(ext)"
            try FileManager.default.copyItem(at:url,to:folder.appendingPathComponent(relative))
            var p = Project(duration:duration,sourceRelativePath:relative); p.name = url.deletingPathExtension().lastPathComponent
            try ProjectStore.save(p,samples:[],to:folder); try? FileManager.default.removeItem(at:folder.appendingPathComponent("recording.inprogress"))
            try load(folder); notice = "导入视频没有鼠标轨迹，可在时间轴上手动添加聚焦。"
        } catch { self.error = error.localizedDescription }
    }
    private func remember(_ url: URL) { recent.removeAll{$0 == url}; recent.insert(url,at:0); recent = Array(recent.prefix(20)); UserDefaults.standard.set(recent.map(\.path),forKey:"recentProjects") }
    func edit(_ mutation: (inout Project) -> Void) {
        guard canEdit, !timelineInteracting, let current = project else { return }
        var candidate = current; mutation(&candidate)
        guard candidate != current else { return }
        do { try candidate.validate(); history.record(current); project = candidate; saveAndRebuild() } catch { self.error = error.localizedDescription }
    }
    func cut(retain: Bool) {
        let range = TimeSpan(start:selectionStart,end:selectionEnd)
        guard range.duration > 0 else { return }
        edit { p in var t = p.timeline; if retain { t.retain(outputRange:range) } else { t.delete(outputRange:range) }; p.kept = t.kept }
        selectedClip = nil; selectionStart = 0; selectionEnd = duration; position = min(position,duration)
    }
    func undo() { guard canEdit, !timelineInteracting, let p = project, let previous = history.undo(current:p) else { return }; project = previous; resetSelection(); saveAndRebuild() }
    func redo() { guard canEdit, !timelineInteracting, let p = project, let next = history.redo(current:p) else { return }; project = next; resetSelection(); saveAndRebuild() }
    private func resetSelection() { selectedClip = nil; selectionStart = 0; selectionEnd = duration; position = min(position,duration) }
    private func saveAndRebuild() {
        guard let project, let root else { return }
        do { try ProjectStore.save(project,samples:samples,to:root); rebuild() } catch { self.error = "自动保存失败：\(error.localizedDescription)" }
    }
    var canSplit: Bool {
        guard canEdit, !timelineInteracting, var timeline = project?.timeline else { return false }
        return timeline.split(at:position)
    }
    func splitAtPlayhead() {
        guard canSplit, var timeline = project?.timeline else { return }
        let at = position
        guard timeline.split(at:at) else { return }
        edit { $0.kept = timeline.kept; $0.version = 2 }
        let splitTime = (at * 30).rounded() / 30
        if let index = timeline.boundaries.dropLast().lastIndex(where:{$0 <= splitTime+0.000001}) {
            selectClip(index,at:splitTime)
        }
    }
    func selectClip(_ index: Int, at time: Double) {
        guard !timelineInteracting, let p = project, p.kept.indices.contains(index) else { return }
        selectedClip = index
        selectionStart = p.timeline.boundaries[index]; selectionEnd = p.timeline.boundaries[index+1]
        seek(time)
    }
    func beginTimelineInteraction() { player.pause(); timelineInteracting = true }
    func commitClipMove(from index: Int,to boundary: Int,snapshot: Project) {
        timelineInteracting = false
        guard project == snapshot else { return }
        var timeline = snapshot.timeline
        guard timeline.moveClip(from:index,toBoundary:boundary) else { return }
        let selected = boundary > index ? boundary-1 : boundary
        position = timeline.boundaries[selected]
        edit { $0.kept = timeline.kept; $0.version = 2 }
        selectClip(selected,at:timeline.boundaries[selected])
    }
    func commitZoomResize(_ candidate: Project,snapshot: Project) {
        timelineInteracting = false
        guard project == snapshot else { return }
        edit { $0 = candidate }
    }
    func regenerate() { edit { $0.zooms = AutoZoomPlanner.plan(samples:samples,duration:$0.duration) } }
    func addZoom() {
        guard let p = project, let start = p.timeline.sourceTime(at:min(position,max(0,duration-0.001))) else { return }
        let end = min(p.duration,start+2.4)
        guard !p.zooms.contains(where:{$0.start < end && $0.end > start}) else { error = "当前位置已有聚焦，请选择该片段调整或删除。"; return }
        let z = ZoomSegment(start:start,end:end,centerX:0.5,centerY:0.5,manual:true)
        edit { $0.zooms.append(z); $0.zooms.sort{$0.start < $1.start} }; selectedZoom = z.id
    }
    func updateZoom(_ z: ZoomSegment) { edit { p in
        if let i = p.zooms.firstIndex(where:{$0.id == z.id}) {
            var updated = z
            if updated.start != p.zooms[i].start || updated.end != p.zooms[i].end { updated.animationRange = nil }
            p.zooms[i] = updated
        }
    } }
    func deleteZoom(_ id: UUID) { edit { $0.zooms.removeAll{$0.id == id} }; selectedZoom = nil }
    func seek(_ value: Double) { position = min(duration,max(0,value)); player.seek(to:CMTime(seconds:position,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero) }
    func togglePlay() { guard renderReady else { return }; if player.rate > 0 { player.pause() } else { if position >= duration-0.05 { seek(0) }; player.play() } }
    func rebuild() {
        renderTask?.cancel(); renderReady = false; player.pause(); thumbnails = []
        let token = UUID(); renderGeneration = token
        guard let p = project, let sourceURL, p.timeline.duration > 0 else { player.replaceCurrentItem(with:nil); return }
        let events = samples, at = min(position,max(0,p.timeline.duration-0.001))
        renderTask = Task {
            do {
                let media = try await MediaRenderer.makeComposition(project:p,samples:events,sourceURL:sourceURL)
                try Task.checkCancellation(); guard token == renderGeneration else { return }
                let item = AVPlayerItem(asset:media.composition); item.videoComposition = media.videoComposition; item.audioMix = media.audioMix
                player.replaceCurrentItem(with:item); seek(at); renderReady = true
                let generator = AVAssetImageGenerator(asset:media.composition); generator.videoComposition = media.videoComposition; generator.maximumSize = CGSize(width:180,height:100)
                var images: [NSImage] = []
                for i in 0..<10 {
                    try Task.checkCancellation()
                    let image = try await generator.image(at:CMTime(seconds:media.duration*Double(i)/10,preferredTimescale:60000)).image
                    images.append(NSImage(cgImage:image,size:.zero))
                }
                if token == renderGeneration { thumbnails = images }
            } catch is CancellationError {} catch { if token == renderGeneration { self.error = "预览生成失败：\(error.localizedDescription)" } }
        }
    }
    func export(settings: ExportSettings, selectionOnly: Bool) {
        guard canExport, var p = project, let sourceURL else { return }
        if selectionOnly { var t = p.timeline; t.retain(outputRange:.init(start:selectionStart,end:selectionEnd)); p.kept = t.kept }
        let panel = NSSavePanel(); panel.allowedContentTypes = [settings.format == .gif ? .gif : .mpeg4Movie]; panel.nameFieldStringValue = p.name + "." + settings.format.rawValue
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try ExportService.validateDestination(destination,sourceURL:sourceURL,projectRoot:root) }
        catch { self.error = error.localizedDescription; return }
        showExport = false; exporting = true; exportProgress = 0; player.pause()
        let events = samples
        exportTask = Task {
            do {
                try await ExportService.export(project:p,samples:events,sourceURL:sourceURL,settings:settings,destination:destination) { [weak self] value in Task { @MainActor in self?.exportProgress = value } }
                exporting = false; notice = "导出完成：\(destination.lastPathComponent)"; NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch is CancellationError { exporting = false; notice = "导出已取消，工程和原始录屏已保留。" }
            catch { exporting = false; self.error = "导出失败：\(error.localizedDescription)" }
        }
    }
    func cancelExport() { exportTask?.cancel() }
    func prepareToQuit() async {
        quitting = true
        if exporting { cancelExport() }
        await work.wait()
        if recording { await stopRecording() }
        await work.wait()
    }
}
func timeLabel(_ seconds: Double) -> String { let n = min(Project.maximumDuration,max(0,seconds.isFinite ? seconds : 0)); return String(format:"%02d:%02d.%01d",Int(n)/60,Int(n)%60,Int(n*10)%10) }
