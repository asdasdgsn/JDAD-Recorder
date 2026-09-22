import SwiftUI
import RecorderCore

struct FocusPositionEditor: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var zoom: ZoomSegment
    @State private var image: NSImage?
    @State private var loadError: String?
    @State private var originalProject: Project?
    @State private var originalRoot: URL?
    @State private var dragOrigin: CameraState?

    private var camera: CameraState {
        FocusFraming.camera(center:CGPoint(x:zoom.centerX,y:zoom.centerY),scale:zoom.scale)
    }
    private var unchanged: Bool { model.project == originalProject && model.root == originalRoot }

    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text("在画面中定位聚焦").font(.title2.weight(.semibold))
                    Text("点击目标位置，或拖动聚焦框。框内就是放大后看到的区域。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName:"xmark") }.buttonStyle(.plain).accessibilityLabel("关闭定位")
            }
            HStack(alignment:.top,spacing:18) {
                VStack(alignment:.leading,spacing:8) {
                    Text("完整原画").font(.caption).foregroundStyle(.secondary)
                    sourceCanvas.frame(height:350)
                    Label("拖动框内任意位置微调 · 点击框外重新定位",systemImage:"hand.draw").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth:.infinity)
                VStack(alignment:.leading,spacing:12) {
                    Text("放大效果").font(.caption).foregroundStyle(.secondary)
                    if let image {
                        magnified(image).frame(height:170).clipShape(RoundedRectangle(cornerRadius:8))
                    } else {
                        Color.black.opacity(0.3).frame(height:170).clipShape(RoundedRectangle(cornerRadius:8))
                    }
                    Text("显示聚焦到位后的画面，播放时仍会平滑放大和还原。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text("缩放倍率").font(.caption)
                    HStack {
                        Slider(value:Binding(get:{zoom.scale},set:{value in
                            let next = FocusFraming.camera(center:CGPoint(x:zoom.centerX,y:zoom.centerY),scale:value)
                            setCamera(next)
                        }),in:1...3,step:0.1).accessibilityLabel("聚焦缩放倍率")
                        Text(String(format:"%.1f×",zoom.scale)).monospacedDigit().frame(width:40)
                    }
                    Button("居中") { setCamera(FocusFraming.camera(center:CGPoint(x:0.5,y:0.5),scale:zoom.scale)) }
                    if zoom.scale == 1 { Text("倍率为 1× 时显示完整画面，调大倍率后可移动聚焦框。").font(.caption).foregroundStyle(.secondary) }
                }.frame(width:220)
            }
            Divider()
            HStack {
                Text(unchanged ? "应用后将固定此聚焦位置，可撤销。" : "工程已改变，请关闭后重新定位。")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("应用聚焦位置") {
                    guard unchanged, image != nil else { return }
                    var updated = zoom
                    updated.centerX = camera.centerX; updated.centerY = camera.centerY; updated.manual = true
                    dismiss()
                    model.updateZoom(updated)
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(image == nil || !unchanged || !model.canEdit || model.timelineInteracting)
            }
        }.padding(24).frame(width:920)
        .task {
            originalProject = model.project; originalRoot = model.root
            do { image = try await model.focusReferenceFrame(for:zoom) }
            catch is CancellationError {} catch { loadError = error.localizedDescription }
        }
    }

    private var sourceCanvas: some View {
        GeometryReader { geometry in
            ZStack(alignment:.topLeading) {
                Color.black.opacity(0.5)
                if let image {
                    let rect = FocusFraming.imageRect(image:image.size,in:geometry.size)
                    let crop = FocusFraming.crop(camera)
                    let focus = CGRect(x:rect.minX+crop.minX*rect.width,y:rect.minY+crop.minY*rect.height,width:crop.width*rect.width,height:crop.height*rect.height)
                    Image(nsImage:image).resizable().frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
                    Path { path in path.addRect(rect); path.addRect(focus) }
                        .fill(.black.opacity(0.48),style:FillStyle(eoFill:true))
                    Rectangle().strokeBorder(accent,lineWidth:2).frame(width:focus.width,height:focus.height).position(x:focus.midX,y:focus.midY)
                    Image(systemName:"plus").font(.system(size:18,weight:.light)).foregroundStyle(.white)
                        .shadow(color:.black,radius:2).position(x:focus.midX,y:focus.midY)
                    // One surface owns the entire gesture, so the moving frame never changes the grab offset.
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:0)
                            .onChanged { value in
                                guard let start = FocusFraming.point(value.startLocation,in:rect) else { return }
                                if dragOrigin == nil {
                                    dragOrigin = crop.contains(start) ? camera : FocusFraming.camera(center:start,scale:zoom.scale)
                                }
                                if let origin = dragOrigin { setCamera(FocusFraming.drag(origin,translation:value.translation,in:rect)) }
                            }
                            .onEnded { _ in dragOrigin = nil })
                        .accessibilityLabel("聚焦定位画布：点击目标位置或拖动聚焦框")
                } else if let loadError {
                    VStack(spacing:10) { Image(systemName:"exclamationmark.triangle"); Text(loadError).multilineTextAlignment(.center) }
                        .padding(20).frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ProgressView("正在加载原画…").frame(maxWidth:.infinity,maxHeight:.infinity)
                }
            }.clipShape(RoundedRectangle(cornerRadius:8))
        }
    }
    private func setCamera(_ value: CameraState) {
        zoom.centerX = value.centerX; zoom.centerY = value.centerY; zoom.scale = value.scale
    }
    private func magnified(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let rect = FocusFraming.imageRect(image:image.size,in:geometry.size)
            let crop = FocusFraming.crop(camera)
            ZStack(alignment:.topLeading) {
                Color.black.opacity(0.5)
                Image(nsImage:image).resizable()
                    .frame(width:rect.width*camera.scale,height:rect.height*camera.scale)
                    .offset(x:-crop.minX*rect.width*camera.scale,y:-crop.minY*rect.height*camera.scale)
                    .frame(width:rect.width,height:rect.height,alignment:.topLeading).clipped()
                    .position(x:rect.midX,y:rect.midY)
            }
        }
    }
}
