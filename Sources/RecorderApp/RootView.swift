import SwiftUI

let accent = Color(red:0.65,green:0.91,blue:0.72)
let canvas = Color(red:0.065,green:0.073,blue:0.086)
struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:26) {
                HStack(spacing:10) { Image(systemName:"record.circle").font(.title).foregroundStyle(accent); VStack(alignment:.leading,spacing:2) { Text("JDAD").font(.system(size:18,weight:.bold,design:.rounded)); Text("RECORDER").font(.system(size:9,weight:.medium)).tracking(2.5).foregroundStyle(.secondary) } }.padding(.top,24)
                VStack(spacing:6) {
                    nav("演示资料库",icon:"square.grid.2x2",page:.library)
                    nav("录制新演示",icon:"record.circle",page:.capture)
                    if model.project != nil { nav("剪辑工作台",icon:"slider.horizontal.3",page:.editor) }
                }
                Spacer()
                VStack(alignment:.leading,spacing:8) {
                    Label("本地工作空间",systemImage:"internaldrive").font(.system(size:12,weight:.medium))
                    Text("录制 · 聚焦 · 分享").font(.system(size:11)).foregroundStyle(.secondary)
                }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                Link(destination:URL(string:"https://jdauto.joyapp.jd.com/")!) {
                    HStack(spacing:6) {
                        Text("发现更多应用与功能").font(.system(size:12,weight:.medium)).lineLimit(1)
                        Spacer(minLength:0)
                        Image(systemName:"arrow.up.right").font(.system(size:10,weight:.semibold))
                    }
                    .padding(.horizontal,10).padding(.vertical,12)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .background(accent.opacity(0.10),in:RoundedRectangle(cornerRadius:8))
                    .contentShape(RoundedRectangle(cornerRadius:8))
                }.buttonStyle(.plain).foregroundStyle(accent)
                    .help("在浏览器中打开更多应用与功能")
                Text("MAC EDITION  /  \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.4")").font(.system(size:9,weight:.medium,design:.monospaced)).foregroundStyle(.tertiary).padding(.bottom,16)
            }.padding(.horizontal,18).frame(width:196).background(Color.black.opacity(0.15))
            Rectangle().fill(.white.opacity(0.06)).frame(width:1)
            VStack(spacing:0) {
                if let notice = model.notice {
                    HStack { Image(systemName:"info.circle"); Text(notice).font(.system(size:12)); Spacer(); Button { model.notice = nil } label: { Image(systemName:"xmark") }.buttonStyle(.plain) }.padding(12).background(accent.opacity(0.09))
                }
                Group { switch model.page { case .library: LibraryView(); case .capture: CaptureView(); case .editor: EditorView() } }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.background(canvas).tint(accent)
        .alert("需要处理",isPresented:Binding(get:{model.error != nil},set:{if !$0 { model.error = nil }})) { Button("知道了",role:.cancel) { model.error = nil } } message: { Text(model.error ?? "") }
        .sheet(isPresented:$model.showExport) { ExportView().environmentObject(model) }
        .overlay {
            if model.exporting {
                Color.black.opacity(0.65).ignoresSafeArea()
                VStack(spacing:18) { Image(systemName:"square.and.arrow.up").font(.largeTitle).foregroundStyle(accent); Text("正在导出演示").font(.title2); ProgressView(value:model.exportProgress).frame(width:280); Text("\(Int(model.exportProgress*100))% · 工程已保留").foregroundStyle(.secondary); Button("取消导出") { model.cancelExport() } }.padding(40).background(canvas,in:RoundedRectangle(cornerRadius:18))
            }
        }
    }
    func nav(_ title: String,icon: String,page: WorkspacePage) -> some View {
        Button { if page == .capture { model.newRecording() } else { model.page = page } } label: {
            HStack(spacing:10) { Image(systemName:icon).frame(width:18); Text(title); Spacer() }.font(.system(size:13,weight:.medium)).padding(.horizontal,12).padding(.vertical,12).background(model.page == page ? accent.opacity(0.11) : .clear,in:RoundedRectangle(cornerRadius:8)).foregroundStyle(model.page == page ? accent : .secondary)
        }.buttonStyle(.plain).disabled(model.recording || model.busy || model.exporting)
    }
}
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:30) {
                HStack { VStack(alignment:.leading,spacing:8) { Text("你的下一次演示，\n从这里开始。").font(.system(size:34,weight:.semibold)); Text("录下操作，让重点自然浮现。").foregroundStyle(.secondary) }; Spacer(); Text("WORKSPACE\n01").font(.system(size:12,design:.monospaced)).multilineTextAlignment(.trailing).foregroundStyle(accent) }
                HStack(spacing:16) {
                    Button { model.newRecording() } label: {
                        VStack(alignment:.leading,spacing:20) { Image(systemName:"record.circle").font(.system(size:36)); Spacer(); Text("录制新演示").font(.title2.weight(.semibold)); Text("屏幕或窗口 · 自动操作聚焦").font(.system(size:13)).opacity(0.7); HStack { Text("开始录制"); Spacer(); Image(systemName:"arrow.up.right") }.font(.system(size:13,weight:.semibold)) }.padding(26).frame(maxWidth:.infinity,alignment:.leading).frame(height:205).background(accent,in:RoundedRectangle(cornerRadius:16)).foregroundStyle(Color.black.opacity(0.85))
                    }.buttonStyle(.plain)
                    Button { model.openPanel() } label: {
                        VStack(alignment:.leading,spacing:20) { Image(systemName:"folder.badge.plus").font(.system(size:32)).foregroundStyle(accent); Spacer(); Text("打开已有内容").font(.title2.weight(.semibold)); Text("继续工程，或导入 MP4 / MOV").font(.system(size:13)).foregroundStyle(.secondary); HStack { Text("浏览文件"); Spacer(); Image(systemName:"arrow.up.right") }.font(.system(size:13,weight:.semibold)) }.padding(26).frame(maxWidth:.infinity,alignment:.leading).frame(height:205).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain)
                }
                HStack { Text("最近的演示").font(.title3.weight(.semibold)); Spacer(); Text("\(model.recent.count) 个工程").font(.caption).foregroundStyle(.secondary) }
                if model.recent.isEmpty {
                    VStack(spacing:12) { Image(systemName:"film.stack").font(.system(size:30)).foregroundStyle(.tertiary); Text("这里将收纳你的演示").foregroundStyle(.secondary); Text("原始录屏和剪辑都保存在这台 Mac 上。").font(.caption).foregroundStyle(.tertiary) }.frame(maxWidth:.infinity).padding(.vertical,40)
                } else {
                    ForEach(model.recent,id:\.self) { url in
                        Button { model.open(url) } label: { HStack(spacing:16) { Image(systemName:"play.rectangle").font(.title2).foregroundStyle(accent).frame(width:50,height:44).background(.white.opacity(0.04),in:RoundedRectangle(cornerRadius:8)); VStack(alignment:.leading,spacing:5) { Text(url.deletingPathExtension().lastPathComponent).lineLimit(1); Text("本地工程 · 可继续编辑").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName:"arrow.right").foregroundStyle(.secondary) }.padding(12).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:10)) }.buttonStyle(.plain)
                    }
                }
            }.padding(40)
        }
    }
}
