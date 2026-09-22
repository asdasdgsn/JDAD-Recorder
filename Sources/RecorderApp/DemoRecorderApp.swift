import SwiftUI
import AppKit

@main
struct DemoRecorderApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("JDAD Recorder") {
            RootView().environmentObject(model).frame(minWidth:1040,minHeight:710).preferredColorScheme(.dark)
                .onOpenURL { model.open($0) }
                .onAppear { delegate.model = model }
        }.defaultSize(width:1280,height:820)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("新建录制") { model.newRecording() }.keyboardShortcut("n").disabled(model.recording || model.busy || model.exporting)
                Button("打开工程或视频…") { model.openPanel() }.keyboardShortcut("o").disabled(model.recording || model.busy || model.exporting)
            }
            CommandMenu("剪辑") {
                Button("在播放头处分割") { model.splitAtPlayhead() }.keyboardShortcut("b").disabled(!model.canSplit)
            }
            CommandGroup(replacing:.undoRedo) {
                Button("撤销") { model.undo() }.keyboardShortcut("z").disabled(!model.history.canUndo || !model.canEdit)
                Button("重做") { model.redo() }.keyboardShortcut("z",modifiers:[.command,.shift]).disabled(!model.history.canRedo || !model.canEdit)
            }
        }
        MenuBarExtra("JDAD Recorder",systemImage:model.recording ? "record.circle.fill" : "record.circle") {
            if model.recording { Button("停止录制并编辑") { Task { await model.stopRecording() } }.disabled(model.busy) }
            else { Button("新建录制") { NSApp.activate(ignoringOtherApps:true); model.newRecording() } }
            Button("显示窗口") { NSApp.activate(ignoringOtherApps:true); NSApp.windows.first(where:{$0.canBecomeMain})?.makeKeyAndOrderFront(nil) }
        }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps:true) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        if model.recording || model.busy || model.exporting {
            Task { await model.prepareToQuit(); NSApp.reply(toApplicationShouldTerminate:true) }
            return .terminateLater
        }
        return .terminateNow
    }
}
