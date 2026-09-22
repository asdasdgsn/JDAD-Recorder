import SwiftUI
import AppKit
import RecorderCore

struct TimelineTrack: View {
    @EnvironmentObject var model: AppModel
    let width: CGFloat
    @State private var snapshot: Project?
    @State private var draft: Project?
    @State private var movingClip: Int?
    @State private var insertion: Int?
    @State private var movement: CGFloat = 0
    @State private var snappedTime: Double?
    @State private var resizing: UUID?
    private var project: Project? { draft ?? model.project }
    private var duration: Double { snapshot?.timeline.duration ?? model.duration }
    private var pixelsPerSecond: CGFloat { width / max(0.001,duration) }
    private func x(_ t: Double) -> CGFloat { t*pixelsPerSecond }
    private func time(_ x: CGFloat) -> Double { Double(x/pixelsPerSecond) }
    private var snapEnabled: Bool { model.snapping && !NSEvent.modifierFlags.contains(.option) }

    var body: some View {
        ZStack(alignment:.topLeading) {
            ruler
            if let p = project {
                ForEach(Array(p.kept.enumerated()),id:\.offset) { index,clip in
                    let start = p.timeline.boundaries[index]
                    clipView(index:index,clip:clip,start:start)
                        .offset(x:x(start),y:27)
                }
                ForEach(p.zooms) { z in
                    ForEach(Array(p.kept.enumerated()),id:\.offset) { index,clip in
                        let start = max(z.start,clip.start), end = min(z.end,clip.end)
                        if end > start {
                            let offset = p.timeline.boundaries[index]
                            focusView(z,clipIndex:index,outputStart:offset+start-clip.start,outputEnd:offset+end-clip.start)
                        }
                    }
                }
            }
            if let movingClip, let snapshot, snapshot.kept.indices.contains(movingClip) {
                HStack(spacing:6) {
                    Image(systemName:"line.3.horizontal")
                    Text("片段 \(movingClip+1)").lineLimit(1)
                }.font(.system(size:11,weight:.semibold))
                    .frame(width:max(20,x(snapshot.kept[movingClip].duration)),height:52)
                    .background(accent.opacity(0.26),in:RoundedRectangle(cornerRadius:5))
                    .overlay(RoundedRectangle(cornerRadius:5).stroke(accent,lineWidth:2))
                    .offset(x:x(snapshot.timeline.boundaries[movingClip])+movement,y:27)
                    .allowsHitTesting(false)
            }
            // Range overlay never eats clip or focus drag gestures.
            Rectangle().fill(accent.opacity(0.06))
                .frame(width:max(0,x(model.selectionEnd-model.selectionStart)),height:54)
                .offset(x:x(model.selectionStart),y:27).allowsHitTesting(false)
            rangeHandle(start:true); rangeHandle(start:false)
            Rectangle().fill(.white.opacity(0.9)).frame(width:1.5,height:115)
                .offset(x:min(width-2,max(0,x(model.position))),y:17).allowsHitTesting(false)
            Image(systemName:"triangle.fill").font(.system(size:9)).rotationEffect(.degrees(180))
                .offset(x:min(width-10,max(0,x(model.position)-4)),y:10).allowsHitTesting(false)
            if let insertion, let snapshot, movingClip != nil {
                marker(at:snapshot.timeline.boundaries[insertion],label:"插入到这里")
            } else if let snappedTime { marker(at:snappedTime,label:"已对齐") }
        }
        .frame(width:width,height:140).coordinateSpace(name:"timeline")
        .onDisappear { cancelDrag() }
    }
    private var ruler: some View {
        ZStack(alignment:.topLeading) {
            Rectangle().fill(.clear).contentShape(Rectangle()).frame(height:24)
                .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { value in
                    guard !model.timelineInteracting else { return }
                    let snap = resolve(time(value.location.x),targets:model.project?.timeline.boundaries ?? [],range:0...max(0,duration))
                    model.seek(snap.time); snappedTime = snap.target
                }.onEnded { _ in snappedTime = nil })
            ForEach(0..<11) { i in
                Text(timeLabel(duration*Double(i)/10)).font(.system(size:9,design:.monospaced)).foregroundStyle(.tertiary)
                    .offset(x:min(width-46,width*Double(i)/10),y:0).allowsHitTesting(false)
            }
        }
    }
    private func clipView(index: Int,clip: TimeSpan,start: Double) -> some View {
        let clipWidth = max(1,x(clip.duration))
        return ZStack(alignment:.topLeading) {
            RoundedRectangle(cornerRadius:5).fill(Color(red:0.17,green:0.24,blue:0.30))
            if !model.thumbnails.isEmpty {
                HStack(spacing:0) {
                    ForEach(0..<3) { i in
                        let t = start + clip.duration*Double(i)/3
                        let sample = min(model.thumbnails.count-1,max(0,Int(t/max(0.001,duration)*Double(model.thumbnails.count))))
                        Image(nsImage:model.thumbnails[sample]).resizable().scaledToFill().frame(width:clipWidth/3,height:52).clipped()
                    }
                }.opacity(0.7).allowsHitTesting(false)
            }
            HStack(spacing:5) {
                Image(systemName:"line.3.horizontal").font(.system(size:9))
                Text("片段 \(index+1)").font(.system(size:10,weight:.semibold)).lineLimit(1)
            }.padding(.horizontal,6).padding(.vertical,3).background(.black.opacity(0.65),in:RoundedRectangle(cornerRadius:4)).padding(4).allowsHitTesting(false)
        }
        .frame(width:clipWidth,height:52).clipped()
        .overlay(RoundedRectangle(cornerRadius:5).stroke(model.selectedClip == index ? accent : .white.opacity(0.5),lineWidth:model.selectedClip == index ? 2 : 1))
        .opacity(movingClip == index ? 0.4 : 1)
        .contentShape(Rectangle())
        .accessibilityLabel("视频片段 \(index+1)，源时间 \(timeLabel(clip.start)) 至 \(timeLabel(clip.end))，可拖动排序")
        .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline"))
            .onChanged { value in
                guard resizing == nil, model.canEdit else { return }
                if movingClip == nil {
                    guard abs(value.translation.width) >= 5, let p = model.project else { return }
                    snapshot = p; movingClip = index; model.beginTimelineInteraction()
                }
                guard movingClip == index, let snapshot else { return }
                movement = value.translation.width
                insertion = snapshot.timeline.insertionBoundary(at:time(value.location.x))
            }
            .onEnded { value in
                if let snapshot, movingClip == index, let insertion {
                    model.commitClipMove(from:index,to:insertion,snapshot:snapshot)
                } else if !model.timelineInteracting {
                    model.selectClip(index,at:min(start+clip.duration,max(start,time(value.location.x))))
                }
                cancelDrag()
            })
        .contextMenu {
            Button("在播放头处分割") { model.splitAtPlayhead() }.disabled(!model.canSplit)
            Button("移到最前") { if let p = model.project { model.commitClipMove(from:index,to:0,snapshot:p) } }.disabled(index == 0 || !model.canEdit)
            Button("移到最后") { if let p = model.project { model.commitClipMove(from:index,to:p.kept.count,snapshot:p) } }.disabled(index == (model.project?.kept.count ?? 0)-1 || !model.canEdit)
        }
    }
    private func focusView(_ z: ZoomSegment,clipIndex: Int,outputStart: Double,outputEnd: Double) -> some View {
        let focusWidth = max(1,x(outputEnd-outputStart))
        let color = z.manual ? Color.orange : accent
        return ZStack {
            RoundedRectangle(cornerRadius:5).fill(color.opacity(model.selectedZoom == z.id ? 0.45 : 0.23))
            RoundedRectangle(cornerRadius:5).stroke(color.opacity(0.8),lineWidth:model.selectedZoom == z.id ? 1.5 : 0.5)
            if focusWidth > 42 { Text(String(format:"%.1f×",z.scale)).font(.system(size:10,weight:.medium,design:.monospaced)).allowsHitTesting(false) }
            HStack(spacing:0) {
                focusHandle(z,clipIndex:clipIndex,edge:.start,outputEdge:outputStart)
                Spacer(minLength:0)
                focusHandle(z,clipIndex:clipIndex,edge:.end,outputEdge:outputEnd)
            }
        }.frame(width:focusWidth,height:28)
            .contentShape(Rectangle())
            .onTapGesture { guard !model.timelineInteracting else { return }; model.selectedZoom = z.id; model.seek(outputStart) }
            .offset(x:x(outputStart),y:99)
    }
    private func focusHandle(_ z: ZoomSegment,clipIndex: Int,edge: ZoomEdge,outputEdge: Double) -> some View {
        RoundedRectangle(cornerRadius:3).fill((z.manual ? Color.orange : accent).opacity(0.9))
            .frame(width:8,height:24)
            .overlay(Capsule().fill(.black.opacity(0.5)).frame(width:1,height:12))
            .contentShape(Rectangle())
            .accessibilityLabel(edge == .start ? "聚焦开始手柄" : "聚焦结束手柄")
            .help("拖动调整聚焦\(edge == .start ? "开始" : "结束")时间")
            .highPriorityGesture(DragGesture(minimumDistance:1,coordinateSpace:.named("timeline"))
                .onChanged { value in
                    guard movingClip == nil, model.canEdit else { return }
                    if snapshot == nil {
                        guard let p = model.project else { return }
                        snapshot = p; resizing = z.id; model.selectedZoom = z.id; model.beginTimelineInteraction()
                    }
                    guard let snapshot, snapshot.kept.indices.contains(clipIndex), let original = snapshot.zooms.first(where:{$0.id == z.id}) else { return }
                    let clip = snapshot.kept[clipIndex], offset = snapshot.timeline.boundaries[clipIndex]
                    let initialEdge = offset + (edge == .start ? max(original.start,clip.start) : min(original.end,clip.end))-clip.start
                    let range = offset...(offset+clip.duration)
                    let targets = snapshot.timeline.boundaries + [model.position] + focusTargets(in:snapshot,excluding:z.id)
                    let snap = resolve(initialEdge+time(value.translation.width),targets:targets,range:range)
                    let candidate = snapshot.resizingZoom(z.id,inClip:clipIndex,edge:edge,toOutputTime:snap.time)
                    draft = candidate
                    if let edited = candidate.zooms.first(where:{$0.id == z.id}), let target = snap.target {
                        let actual = offset+(edge == .start ? max(edited.start,clip.start) : min(edited.end,clip.end))-clip.start
                        snappedTime = abs(actual-target) < 0.00001 ? target : nil
                    } else { snappedTime = nil }
                }
                .onEnded { _ in
                    if let snapshot, let draft { model.commitZoomResize(draft,snapshot:snapshot) }
                    cancelDrag()
                })
    }
    private func rangeHandle(start: Bool) -> some View {
        // Separate strip below video clips keeps range selection distinct from clip movement.
        RoundedRectangle(cornerRadius:2).fill(accent).frame(width:9,height:10)
            .offset(x:min(width-9,max(0,x(start ? model.selectionStart : model.selectionEnd)-(start ? 0 : 9))),y:82)
            .accessibilityLabel(start ? "选区起点" : "选区终点")
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { value in
                guard model.canEdit, !model.timelineInteracting else { return }
                let targets = (model.project?.timeline.boundaries ?? [])+[model.position]
                let snap = resolve(time(value.location.x),targets:targets,range:0...max(0,duration))
                if start { model.selectionStart = min(snap.time,model.selectionEnd) } else { model.selectionEnd = max(snap.time,model.selectionStart) }
                snappedTime = snap.target
            }.onEnded { _ in snappedTime = nil })
    }
    private func resolve(_ value: Double,targets: [Double],range: ClosedRange<Double>) -> SnapResult {
        TimelineSnap.resolve(value,targets:snapEnabled ? targets : [],tolerance:Double(8/pixelsPerSecond),range:range)
    }
    private func focusTargets(in p: Project,excluding id: UUID) -> [Double] {
        var result: [Double] = []
        for (index,clip) in p.kept.enumerated() {
            let offset = p.timeline.boundaries[index]
            for z in p.zooms where z.id != id {
                let start = max(z.start,clip.start), end = min(z.end,clip.end)
                if end > start { result += [offset+start-clip.start,offset+end-clip.start] }
            }
        }
        return result
    }
    private func marker(at time: Double,label: String) -> some View {
        ZStack(alignment:.topLeading) {
            Rectangle().fill(accent).frame(width:2,height:115)
            Text(label).font(.system(size:9,weight:.semibold)).padding(.horizontal,5).padding(.vertical,3).background(accent,in:RoundedRectangle(cornerRadius:3)).foregroundStyle(.black).offset(x:4,y:0)
        }.offset(x:min(width-2,max(0,x(time))),y:20).allowsHitTesting(false)
    }
    private func cancelDrag() { snapshot = nil; draft = nil; movingClip = nil; insertion = nil; movement = 0; resizing = nil; snappedTime = nil; model.timelineInteracting = false }
}
