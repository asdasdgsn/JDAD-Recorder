import SwiftUI
import AVKit
import RecorderCore

struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView { let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.videoGravity = .resizeAspect; return view }
    func updateNSView(_ view: AVPlayerView,context: Context) { view.player = player }
}
struct EditorView: View {
    @EnvironmentObject var model: AppModel
    @State private var regenerateConfirm = false
    @State private var timelineScale = 1.0
    var body: some View {
        VStack(spacing:0) {
            HStack(spacing:16) {
                VStack(alignment:.leading,spacing:4) { Text(model.project?.name ?? "剪辑工作台").font(.system(size:17,weight:.semibold)).lineLimit(1); Text("原始录屏保留 · 更改自动保存").font(.system(size:11)).foregroundStyle(.secondary) }
                Spacer()
                Button { model.undo() } label: { Image(systemName:"arrow.uturn.backward") }.disabled(!model.history.canUndo || !model.canEdit).help("撤销 ⌘Z")
                Button { model.redo() } label: { Image(systemName:"arrow.uturn.forward") }.disabled(!model.history.canRedo || !model.canEdit).help("重做 ⇧⌘Z")
                Button { model.showExport = true } label: { Label("导出",systemImage:"square.and.arrow.up").padding(.horizontal,8) }.buttonStyle(.borderedProminent).disabled(!model.canExport)
            }.padding(20)
            Divider().opacity(0.4)
            HStack(spacing:0) {
                VStack(spacing:12) {
                    ZStack {
                        Color.black.opacity(0.45)
                        if model.duration > 0 { PlayerSurface(player:model.player) }
                        else { VStack(spacing:12) { Image(systemName:"film").font(.largeTitle); Text("当前没有保留的片段"); Button("撤销删除") { model.undo() }.disabled(!model.history.canUndo) }.foregroundStyle(.secondary) }
                        if !model.renderReady && model.duration > 0 { ProgressView("正在准备预览…").padding(20).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:12)) }
                    }.clipShape(RoundedRectangle(cornerRadius:10))
                    HStack { Text("预览").font(.caption).foregroundStyle(.tertiary); Spacer(); Button { model.togglePlay() } label: { Image(systemName:model.player.rate > 0 ? "pause.fill" : "play.fill").frame(width:28) }.buttonStyle(.plain).keyboardShortcut(.space,modifiers:[]).disabled(!model.renderReady); Text("\(timeLabel(model.position)) / \(timeLabel(model.duration))").font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary); Spacer(); Text("30 FPS").font(.system(size:10,design:.monospaced)).foregroundStyle(.tertiary) }
                }.padding(20).frame(maxWidth:.infinity)
                Divider().opacity(0.4)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text("操作聚焦").font(.headline)
                        Toggle("自动缩放",isOn:Binding(get:{model.project?.automaticZoomEnabled ?? true},set:{value in model.edit{$0.automaticZoomEnabled = value}})).font(.system(size:12))
                        Text("点击会触发平滑放大。选中片段可以调整画面中心与倍率。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        HStack { Button("添加聚焦") { model.addZoom() }; Button { regenerateConfirm = true } label: { Image(systemName:"arrow.clockwise") }.help("重新生成自动聚焦") }
                        Divider()
                        if let z = model.project?.zooms.first(where:{$0.id == model.selectedZoom}) {
                            ZoomInspector(zoom:z).id(z)
                        } else {
                            Image(systemName:"cursorarrow.click.2").font(.system(size:28)).foregroundStyle(accent.opacity(0.7)).padding(.top,8)
                            Text("选择一个聚焦片段").font(.system(size:13,weight:.medium))
                            Text("在下方绿色轨道点击片段，或在当前播放位置添加聚焦。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                        }
                        Divider()
                        Text("聚焦列表").font(.caption).foregroundStyle(.secondary)
                        ForEach(model.project?.zooms ?? []) { z in
                            Button { model.selectedZoom = z.id; if let t = model.project?.timeline.outputTime(at:z.start) { model.seek(t) } } label: {
                                HStack { Circle().fill(z.manual ? Color.orange : accent).frame(width:5,height:5); Text(timeLabel(z.start)).font(.system(size:11,design:.monospaced)); Spacer(); Text(String(format:"%.1f×",z.scale)).font(.caption) }.padding(8).background(model.selectedZoom == z.id ? .white.opacity(0.08) : .clear,in:RoundedRectangle(cornerRadius:6))
                            }.buttonStyle(.plain)
                        }
                    }.padding(18)
                }.frame(width:240).background(.black.opacity(0.1)).disabled(!model.canEdit)
            }
            Divider().opacity(0.4)
            VStack(spacing:12) {
                HStack(spacing:12) {
                    Text("时间轴").font(.system(size:12,weight:.semibold))
                    Text("拖动白色播放头定位；拖动两端绿色手柄选区").font(.system(size:11)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName:"minus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
                    Slider(value:$timelineScale,in:1...6).frame(width:85)
                    Image(systemName:"plus.magnifyingglass").font(.caption).foregroundStyle(.secondary)
                }
                GeometryReader { outer in
                    ScrollView(.horizontal) { TimelineTrack(width:max(1,outer.size.width)*timelineScale).frame(width:max(1,outer.size.width)*timelineScale,height:114) }.frame(height:126)
                }.frame(height:126)
                HStack(spacing:12) {
                    Label("选区",systemImage:"selection.pin.in.out").font(.caption).foregroundStyle(.secondary)
                    timeField("起点",value:$model.selectionStart,range:0...max(0,model.selectionEnd))
                    Text("—").foregroundStyle(.tertiary)
                    timeField("终点",value:$model.selectionEnd,range:min(model.selectionStart,model.duration)...max(model.selectionStart,model.duration))
                    Spacer()
                    Button("仅保留选区") { model.cut(retain:true) }.disabled(!model.canEdit || model.selectionEnd <= model.selectionStart)
                    Button(role:.destructive) { model.cut(retain:false) } label: { Label("删除选区",systemImage:"scissors") }.disabled(!model.canEdit || model.selectionEnd <= model.selectionStart)
                }
            }.padding(18).background(.black.opacity(0.15))
        }
        .confirmationDialog("重新生成聚焦将替换所有现有聚焦，包括手动调整。",isPresented:$regenerateConfirm) { Button("重新生成",role:.destructive) { model.regenerate() }; Button("取消",role:.cancel) {} }
    }
    func timeField(_ title: String,value: Binding<Double>,range: ClosedRange<Double>) -> some View {
        HStack(spacing:4) { Text(title).font(.caption).foregroundStyle(.tertiary); TextField("秒",value:Binding(get:{value.wrappedValue},set:{value.wrappedValue = $0.isFinite ? min(range.upperBound,max(range.lowerBound,$0)) : range.lowerBound}),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width:68); Text("秒").font(.caption).foregroundStyle(.tertiary) }.disabled(!model.canEdit)
    }
}
struct TimelineTrack: View {
    @EnvironmentObject var model: AppModel
    let width: CGFloat
    func x(_ time: Double) -> CGFloat { width*min(1,max(0,time/max(0.001,model.duration))) }
    var body: some View {
        ZStack(alignment:.topLeading) {
            ForEach(0..<11) { i in Text(timeLabel(model.duration*Double(i)/10)).font(.system(size:9,design:.monospaced)).foregroundStyle(.tertiary).offset(x:min(width-46,width*Double(i)/10),y:0) }
            HStack(spacing:1) {
                if model.thumbnails.isEmpty { Rectangle().fill(.white.opacity(0.04)) }
                else { ForEach(Array(model.thumbnails.enumerated()),id:\.offset) { _,image in Image(nsImage:image).resizable().scaledToFill().frame(width:width/CGFloat(model.thumbnails.count),height:46).clipped() } }
            }.frame(width:width,height:46).clipped().cornerRadius(5).offset(y:23)
            Rectangle().fill(accent.opacity(0.13)).frame(width:max(0,x(model.selectionEnd)-x(model.selectionStart)),height:46).overlay(Rectangle().stroke(accent,lineWidth:1)).offset(x:x(model.selectionStart),y:23)
            // Gestures here seek; handles and zoom buttons sit above this layer.
            Rectangle().fill(.clear).contentShape(Rectangle()).frame(width:width,height:69).gesture(DragGesture(minimumDistance:0).onChanged { model.seek(Double($0.location.x/width)*model.duration) })
            if let p = model.project {
                ForEach(p.zooms) { z in
                    ForEach(Array(p.kept.enumerated()),id:\.offset) { index,span in
                        let start = max(z.start,span.start), end = min(z.end,span.end)
                        if end > start {
                            let preceding = p.kept.prefix(index).reduce(0){$0+$1.duration}
                            let outputStart = preceding+start-span.start
                            Button { model.selectedZoom = z.id; model.seek(outputStart) } label: {
                                Text(String(format:"%.1f×",z.scale)).font(.system(size:9,weight:.medium,design:.monospaced)).lineLimit(1).frame(width:max(6,x(end-start)),height:23).background((z.manual ? Color.orange : accent).opacity(model.selectedZoom == z.id ? 0.65 : 0.25),in:RoundedRectangle(cornerRadius:4))
                            }.buttonStyle(.plain).offset(x:x(outputStart),y:78)
                        }
                    }
                }
            }
            handle(start:true); handle(start:false)
            Rectangle().fill(.white).frame(width:1.5,height:88).offset(x:min(width-2,x(model.position)),y:18).allowsHitTesting(false)
            Image(systemName:"triangle.fill").font(.system(size:9)).rotationEffect(.degrees(180)).offset(x:min(width-10,max(0,x(model.position)-4)),y:10).allowsHitTesting(false)
        }.frame(width:width,height:110).coordinateSpace(name:"track")
    }
    func handle(start: Bool) -> some View {
        RoundedRectangle(cornerRadius:3).fill(accent).frame(width:7,height:50).overlay(Capsule().fill(.black.opacity(0.4)).frame(width:1,height:15)).offset(x:min(width-7,max(0,x(start ? model.selectionStart : model.selectionEnd)-(start ? 0 : 7))),y:21)
            .gesture(DragGesture(coordinateSpace:.named("track")).onChanged { value in let time = max(0,min(model.duration,Double(value.location.x/width)*model.duration)); if start { model.selectionStart = min(time,model.selectionEnd) } else { model.selectionEnd = max(time,model.selectionStart) } }).disabled(!model.canEdit)
    }
}
struct ZoomInspector: View {
    @EnvironmentObject var model: AppModel
    @State var zoom: ZoomSegment
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("聚焦设置").font(.system(size:12,weight:.semibold)); Spacer(); Text(zoom.manual ? "手动" : "自动").font(.caption).foregroundStyle(.secondary) }
            Text("时间使用原始录屏的秒数").font(.system(size:10)).foregroundStyle(.tertiary)
            HStack { TextField("开始",value:$zoom.start,format:.number.precision(.fractionLength(2))); Text("—"); TextField("结束",value:$zoom.end,format:.number.precision(.fractionLength(2))) }.textFieldStyle(.roundedBorder)
            HStack { Text("缩放倍率"); Spacer(); Text(String(format:"%.1f×",zoom.scale)).foregroundStyle(accent) }.font(.caption)
            Slider(value:$zoom.scale,in:1...3,step:0.1)
            Text("画面中心 · 水平").font(.caption).foregroundStyle(.secondary)
            Slider(value:$zoom.centerX,in:0...1)
            Text("画面中心 · 垂直").font(.caption).foregroundStyle(.secondary)
            Slider(value:$zoom.centerY,in:0...1)
            Button("应用调整") { zoom.manual = true; model.updateZoom(zoom) }.buttonStyle(.borderedProminent)
            Button("删除此聚焦",role:.destructive) { model.deleteZoom(zoom.id) }.font(.caption)
        }
    }
}
