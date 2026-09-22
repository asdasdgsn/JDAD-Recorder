import SwiftUI
import AppKit
import RecorderMedia
struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
        VStack(alignment:.leading,spacing:24) {
            VStack(alignment:.leading,spacing:8) { Text("录制新演示").font(.system(size:28,weight:.semibold)); Text("选好画面，专注操作。缩放会在录制后自动生成。").foregroundStyle(.secondary) }
            VStack(spacing:24) {
                if model.recording || model.countdown != nil { ZStack { RoundedRectangle(cornerRadius:20).fill(accent.opacity(0.07)).frame(width:130,height:100); Image(systemName:model.recording ? "waveform" : "macwindow").font(.system(size:46)).foregroundStyle(accent) } }
                if let count = model.countdown { Text("\(count)").font(.system(size:64,weight:.light,design:.rounded)); Text("准备开始…").foregroundStyle(.secondary) }
                else if model.recording {
                    Text("正在录制").font(.title2)
                    if let started = model.recordingStarted { Text(started,style:.timer).font(.system(size:36,weight:.light,design:.monospaced)) }
                    Text("你可以切换到演示窗口，菜单栏也可以停止录制。").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await model.stopRecording() } } label: { Label(model.busy ? "正在保存…" : "停止录制并编辑",systemImage:"stop.fill").padding(.horizontal,20).padding(.vertical,8) }.buttonStyle(.borderedProminent).disabled(model.busy)
                } else {
                    VStack(alignment:.leading,spacing:18) {
                        HStack { Text("录制来源").font(.headline); Spacer(); Button("刷新预览") { Task { await model.refreshSources() } }.disabled(model.busy) }
                        Picker("录制方式",selection:$model.regionMode) {
                            Text("屏幕 / 窗口").tag(false)
                            Text("指定区域").tag(true)
                        }.pickerStyle(.segmented)
                        sourceGrid
                        if model.regionMode {
                            HStack {
                                VStack(alignment:.leading,spacing:5) {
                                    if let region = model.captureRegion {
                                        Label("已框选 \(Int(region.width)) × \(Int(region.height)) 点",systemImage:"crop").font(.system(size:13,weight:.medium))
                                        Text("只录制框内画面，自动聚焦跟随区域内操作。").font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text("在屏幕上拖出要录制的范围").font(.system(size:13,weight:.medium))
                                        Text("框选后可移动、调整大小；Esc 取消。").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(model.captureRegion == nil ? "框选区域" : "重新框选") { Task { await model.chooseRecordingRegion() } }.disabled(model.sourceID.isEmpty)
                            }
                        }
                        Divider()
                        Toggle("录制麦克风",isOn:$model.microphone)
                        if model.microphone { Picker("麦克风",selection:$model.microphoneID) { Text("系统默认").tag(""); ForEach(model.microphones,id:\.uniqueID) { Text($0.localizedName).tag($0.uniqueID) } } }
                        HStack(alignment:.top,spacing:10) { Image(systemName:"cursorarrow.motionlines").foregroundStyle(accent); Text("自动聚焦点击区域，保留原始录屏。\n录完后可调整每一段缩放。").font(.caption).foregroundStyle(.secondary) }
                    }.padding(24).frame(maxWidth:760).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14)).disabled(model.busy)
                    Button { Task { await model.startRecording() } } label: { Label("开始录制",systemImage:"record.circle").font(.headline).padding(.horizontal,36).padding(.vertical,10) }.buttonStyle(.borderedProminent).disabled(!model.canStartRecording)
                    if model.busy { ProgressView().controlSize(.small) }
                    Button("打开录屏权限设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity)
            Text("视频保存在 影片 / Demo Recorder。录制时仅保存鼠标位置和点击，不记录键盘文字。").font(.caption).foregroundStyle(.tertiary)
        }.padding(28)
        }
    }
    private var sourceGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.availableCaptureSources.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "rectangle.on.rectangle.slash").font(.title2)
                        Text(model.busy ? "正在查找录制来源…" : "暂无可录制画面")
                        Text("打开目标窗口后，点击刷新预览。").font(.caption)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
                } else {
                    sourceSection("屏幕", sources: model.availableCaptureSources.filter { !$0.isWindow })
                    sourceSection("应用窗口", sources: model.availableCaptureSources.filter { $0.isWindow })
                }
            }.padding(3)
        }.frame(height: 300)
    }
    @ViewBuilder
    private func sourceSection(_ title: String, sources: [CaptureSource]) -> some View {
        if !sources.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175, maximum: 250), spacing: 12)], spacing: 12) {
                ForEach(sources) { source in
                    sourceCard(source)
                }
            }
        }
    }
    private func sourceCard(_ source: CaptureSource) -> some View {
        let selected = model.sourceID == source.id
        return Button { model.sourceID = source.id } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(.black.opacity(0.3))
                    if let image = model.sourceThumbnails[source.id] {
                        Image(nsImage: image).resizable().scaledToFit().padding(3)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: source.isWindow ? "macwindow" : "display").font(.title2)
                            Text("暂无预览，仍可录制").font(.system(size: 10))
                        }.foregroundStyle(.secondary)
                    }
                }.frame(height: 100)
                HStack(alignment: .top, spacing: 6) {
                    Text(source.title).font(.system(size: 12, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? accent : Color.secondary)
                }.frame(height: 32, alignment: .top)
            }.padding(9)
                .background(selected ? accent.opacity(0.10) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? accent : Color.white.opacity(0.10), lineWidth: selected ? 2 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .help(source.title)
            .accessibilityLabel(source.title)
            .accessibilityValue(selected ? "已选中" : "未选中")
            .task(id: model.sourcePreviewGeneration) { await model.loadSourceThumbnail(source) }
    }

}
