import AppKit
import SwiftUI

/// Non-activating controls stay clickable while the user demonstrates another app.
/// CaptureService excludes this application's windows from display/region capture;
/// window capture includes only the selected external window.
@MainActor
final class RecordingControls: NSObject {
    private var panel: RecordingControlPanel?
    private var displayID: CGDirectDisplayID?

    func show(on screen: NSScreen, started: Date, stop: @escaping () -> Void) {
        hide()
        displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        let panel = RecordingControlPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 48),
                                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "JDAD Recorder · 停止录制"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: RecordingStopButton(started: started, stop: stop))
        self.panel = panel
        position(on: screen)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        panel.orderFrontRegardless()
    }

    func hide() {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        displayID = nil
    }

    private func position(on screen: NSScreen) {
        guard let panel else { return }
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                     y: area.maxY - panel.frame.height - 12))
    }

    @objc private func screenParametersChanged() {
        let target = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        } ?? NSScreen.main ?? NSScreen.screens.first
        if let target { position(on: target) }
    }
}

private final class RecordingControlPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct RecordingStopButton: View {
    let started: Date
    let stop: () -> Void
    @State private var stopping = false

    var body: some View {
        Button {
            guard !stopping else { return }
            stopping = true
            stop()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "stop.circle.fill").font(.system(size: 24)).foregroundStyle(.red)
                Text(stopping ? "正在停止…" : "停止录制").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Text(started, style: .timer).monospacedDigit().font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).frame(width: 260, height: 48)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(stopping)
        .help("停止录制并进入剪辑")
        .accessibilityLabel("停止录制并进入剪辑")
        .preferredColorScheme(.dark)
    }
}
