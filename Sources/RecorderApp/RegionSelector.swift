import AppKit
import RecorderCore

@MainActor
final class RegionSelector {
    private var panel: RegionPanel?
    private var completion: ((CGRect?) -> Void)?
    private weak var previousWindow: NSWindow?

    func select(on screen: NSScreen, initial: CGRect?) async -> CGRect? {
        cancel()
        previousWindow = NSApp.keyWindow
        previousWindow?.orderOut(nil)
        return await withCheckedContinuation { continuation in
            completion = { continuation.resume(returning:$0) }
            let panel = RegionPanel(contentRect:screen.frame,styleMask:.borderless,backing:.buffered,defer:false)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.title = "框选录制区域"
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            let view = RegionSelectionView(frame:CGRect(origin:.zero,size:screen.frame.size))
            view.selection = initial
            view.finish = { [weak self] rect in self?.finish(rect) }
            panel.contentView = view
            self.panel = panel
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps:true)
        }
    }
    func cancel() { finish(nil) }
    private func finish(_ rect: CGRect?) {
        guard let completion else { return }
        self.completion = nil
        panel?.orderOut(nil); panel?.close(); panel = nil
        previousWindow?.makeKeyAndOrderFront(nil)
        completion(rect)
    }
}
private final class RegionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
private final class RegionSelectionView: NSView {
    var selection: CGRect? { didSet { needsDisplay = true; confirm.isEnabled = validSelection } }
    var finish: ((CGRect?) -> Void)?
    private var anchor = CGPoint.zero
    private var moving: CGRect?
    private let confirm = NSButton(title:"确认区域 ↩",target:nil,action:nil)
    private let cancelButton = NSButton(title:"取消 Esc",target:nil,action:nil)
    private let hint = NSTextField(labelWithString:"拖动框选 · 框内拖动移动 · 拖动四角调整")
    private let toolbar = NSVisualEffectView()
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var validSelection: Bool { (selection?.width ?? 0) >= 32 && (selection?.height ?? 0) >= 32 }
    override init(frame: NSRect) {
        super.init(frame:frame)
        toolbar.material = .hudWindow; toolbar.blendingMode = .withinWindow; toolbar.state = .active
        toolbar.wantsLayer = true; toolbar.layer?.cornerRadius = 12
        hint.font = .systemFont(ofSize:13); hint.textColor = .labelColor
        confirm.target = self; confirm.action = #selector(accept); confirm.bezelStyle = .rounded; confirm.isEnabled = false
        cancelButton.target = self; cancelButton.action = #selector(cancelSelection); cancelButton.bezelStyle = .rounded
        toolbar.addSubview(hint); toolbar.addSubview(confirm); toolbar.addSubview(cancelButton); addSubview(toolbar)
        setAccessibilityLabel("录制区域选择：拖动框选，回车确认，Escape 取消")
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        toolbar.frame = CGRect(x:max(8,(bounds.width-640)/2),y:24,width:min(640,bounds.width-16),height:54)
        hint.frame = CGRect(x:16,y:18,width:340,height:20)
        cancelButton.frame = CGRect(x:toolbar.bounds.width-214,y:12,width:94,height:30)
        confirm.frame = CGRect(x:toolbar.bounds.width-116,y:12,width:106,height:30)
    }
    override func draw(_ dirtyRect: NSRect) {
        let shade = NSBezierPath(rect:bounds); shade.windingRule = .evenOdd
        if let selection { shade.appendRect(selection) }
        NSColor.black.withAlphaComponent(0.48).setFill(); shade.fill()
        guard let selection else { return }
        NSColor.systemGreen.setStroke(); let outline = NSBezierPath(rect:selection); outline.lineWidth = 2; outline.stroke()
        for corner in corners(selection) {
            NSColor.white.setFill(); NSBezierPath(roundedRect:CGRect(x:corner.x-4,y:corner.y-4,width:8,height:8),xRadius:2,yRadius:2).fill()
        }
        let text = validSelection ? "\(Int(selection.width)) × \(Int(selection.height)) 点" : "区域至少 32 × 32"
        let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize:13,weight:.medium),.foregroundColor:NSColor.white]
        let size = (text as NSString).size(withAttributes:attributes)
        let label = CGRect(x:min(max(8,selection.midX-size.width/2-8),bounds.width-size.width-24),y:min(bounds.height-30,max(84,selection.maxY+8)),width:size.width+16,height:24)
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect:label,xRadius:5,yRadius:5).fill()
        (text as NSString).draw(at:CGPoint(x:label.minX+8,y:label.minY+4),withAttributes:attributes)
    }
    override func mouseDown(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        anchor = point; moving = nil
        if let selection {
            let points = corners(selection)
            if let index = points.firstIndex(where:{hypot($0.x-point.x,$0.y-point.y) <= 12}) {
                anchor = points[3-index]
                return
            }
            if selection.contains(point) { moving = selection; NSCursor.closedHand.set(); return }
        }
        selection = CGRect(origin:point,size:.zero)
    }
    override func mouseDragged(with event:NSEvent) {
        let point = convert(event.locationInWindow,from:nil)
        if let moving {
            selection = RecordingRegion.moving(moving,by:CGSize(width:point.x-anchor.x,height:point.y-anchor.y),in:bounds.size)
        } else { selection = RecordingRegion.selection(from:anchor,to:point,in:bounds.size) }
    }
    override func mouseUp(with event:NSEvent) {
        moving = nil; window?.invalidateCursorRects(for:self)
    }
    override func resetCursorRects() {
        addCursorRect(bounds,cursor:.crosshair)
        if let selection { addCursorRect(selection.insetBy(dx:10,dy:10),cursor:.openHand) }
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 { cancelSelection() }
        else if event.keyCode == 36 || event.keyCode == 76 { accept() }
        else { super.keyDown(with:event) }
    }
    @objc private func accept() { if validSelection { finish?(selection) } }
    @objc private func cancelSelection() { finish?(nil) }
    private func corners(_ rect:CGRect) -> [CGPoint] {
        [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)]
    }
}
