import SwiftUI
import RecorderMedia
struct ExportView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var format = ExportFormat.mp4
    @State private var mp4Size = 1920
    @State private var gifSize = 960
    @State private var fps = 15
    @State private var selectedOnly = false
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack { VStack(alignment:.leading,spacing:6) { Text("导出演示").font(.title2.weight(.semibold)); Text("让团队看见你的想法。").foregroundStyle(.secondary) }; Spacer(); Button { dismiss() } label: { Image(systemName:"xmark") }.buttonStyle(.plain) }
            Picker("格式",selection:$format) { Text("MP4 视频").tag(ExportFormat.mp4); Text("GIF 动图").tag(ExportFormat.gif) }.pickerStyle(.segmented)
            if format == .mp4 {
                Picker("画面尺寸",selection:$mp4Size) { Text("1080p · 最长边 1920").tag(1920); Text("720p · 最长边 1280").tag(1280); Text("原始尺寸").tag(0) }
                Text("H.264 · 30 fps · 保留录制的声音\n维持原始比例，不放大小尺寸素材。").font(.caption).foregroundStyle(.secondary)
            } else {
                Picker("最长边",selection:$gifSize) { Text("640 px · 更小文件").tag(640); Text("960 px · 推荐").tag(960); Text("1280 px · 更清晰").tag(1280) }
                Picker("帧率",selection:$fps) { Text("10 fps").tag(10); Text("15 fps").tag(15); Text("20 fps").tag(20) }
                Text("GIF 无声音、循环播放。长视频会产生较大文件，建议选取短片段后导出。").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("仅导出当前选区",isOn:$selectedOnly)
            HStack { Text("导出时长").foregroundStyle(.secondary); Spacer(); Text(timeLabel(selectedOnly ? model.selectionEnd-model.selectionStart : model.duration)).monospacedDigit() }
            HStack { Button("取消") { dismiss() }; Spacer(); Button("选择位置并导出…") { model.export(settings:.init(format:format,longEdge:format == .mp4 ? mp4Size : gifSize,fps:format == .mp4 ? 30 : fps),selectionOnly:selectedOnly) }.buttonStyle(.borderedProminent).disabled(selectedOnly && model.selectionEnd <= model.selectionStart) }
        }.padding(28).frame(width:430).tint(accent)
    }
}
