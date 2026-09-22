import SwiftUI
import AppKit
struct CaptureView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment:.leading,spacing:28) {
            VStack(alignment:.leading,spacing:8) { Text("录制新演示").font(.system(size:28,weight:.semibold)); Text("选好画面，专注操作。缩放会在录制后自动生成。").foregroundStyle(.secondary) }
            Spacer(minLength:0)
            VStack(spacing:24) {
                ZStack { RoundedRectangle(cornerRadius:20).fill(accent.opacity(0.07)).frame(width:130,height:100); Image(systemName:model.recording ? "waveform" : "macwindow").font(.system(size:46)).foregroundStyle(accent) }
                if let count = model.countdown { Text("\(count)").font(.system(size:64,weight:.light,design:.rounded)); Text("准备开始…").foregroundStyle(.secondary) }
                else if model.recording {
                    Text("正在录制").font(.title2)
                    if let started = model.recordingStarted { Text(started,style:.timer).font(.system(size:36,weight:.light,design:.monospaced)) }
                    Text("你可以切换到演示窗口，菜单栏也可以停止录制。").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await model.stopRecording() } } label: { Label(model.busy ? "正在保存…" : "停止录制并编辑",systemImage:"stop.fill").padding(.horizontal,20).padding(.vertical,8) }.buttonStyle(.borderedProminent).disabled(model.busy)
                } else {
                    VStack(alignment:.leading,spacing:18) {
                        HStack { Text("录制来源").font(.headline); Spacer(); Button("刷新列表") { Task { await model.refreshSources() } }.disabled(model.busy) }
                        Picker("画面",selection:$model.sourceID) { Text("请选择屏幕或窗口").tag(""); ForEach(model.sources) { source in Text(source.title).tag(source.id) } }.labelsHidden()
                        Divider()
                        Toggle("录制麦克风",isOn:$model.microphone)
                        if model.microphone { Picker("麦克风",selection:$model.microphoneID) { Text("系统默认").tag(""); ForEach(model.microphones,id:\.uniqueID) { Text($0.localizedName).tag($0.uniqueID) } } }
                        HStack(alignment:.top,spacing:10) { Image(systemName:"cursorarrow.motionlines").foregroundStyle(accent); Text("自动聚焦点击区域，保留原始录屏。\n录完后可调整每一段缩放。").font(.caption).foregroundStyle(.secondary) }
                    }.padding(24).frame(width:460).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:14)).disabled(model.busy)
                    Button { Task { await model.startRecording() } } label: { Label("开始录制",systemImage:"record.circle").font(.headline).padding(.horizontal,36).padding(.vertical,10) }.buttonStyle(.borderedProminent).disabled(model.busy || model.sourceID.isEmpty)
                    if model.busy { ProgressView().controlSize(.small) }
                    Button("打开录屏权限设置") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity)
            Spacer(minLength:0)
            Text("视频保存在 影片 / Demo Recorder。录制时仅保存鼠标位置和点击，不记录键盘文字。").font(.caption).foregroundStyle(.tertiary)
        }.padding(36)
    }
}
