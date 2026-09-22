import AppKit
import CoreMedia
import RecorderCore

@MainActor
final class PointerRecorder {
    private var timer: Timer?
    private var global: Any?
    private var local: Any?
    private var events: [PointerSample] = []
    private var geometry: (() -> CGRect?)?
    var observedClicks: Int { events.filter(\.clicked).count }
    func start(geometry: @escaping () -> CGRect?) {
        stopMonitoring(); events = []; self.geometry = geometry
        global = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample(clicked:true) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.sample(clicked:true) }; return event
        }
        timer = Timer.scheduledTimer(withTimeInterval:1.0/60,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.sample(clicked:false) } }
    }
    private func sample(clicked: Bool) {
        guard let rect = geometry?(), let event = CGEvent(source:nil), let point = PointerMapping.normalize(point:event.location,contentRect:rect) else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        events.append(.init(time:time,x:point.x,y:point.y,clicked:clicked))
    }
    func stop(anchor: Double, duration: Double) -> [PointerSample] {
        stopMonitoring()
        return events.compactMap { s in
            let t = s.time-anchor
            return t >= 0 && t <= duration ? .init(time:t,x:s.x,y:s.y,clicked:s.clicked) : nil
        }
    }
    func stopMonitoring() {
        timer?.invalidate(); timer = nil
        if let global { NSEvent.removeMonitor(global) }; global = nil
        if let local { NSEvent.removeMonitor(local) }; local = nil
        geometry = nil
    }
}
