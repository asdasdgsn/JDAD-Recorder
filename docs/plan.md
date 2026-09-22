# Mac Demo Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a runnable macOS application for recording feature demonstrations, editable automatic pointer zoom, simple cuts, and MP4/GIF export.

**Architecture:** A native app owns capture, editing, and export state. A portable Swift core owns source-time intervals, pointer normalization, camera evaluation, and project metadata. A shared AVFoundation composition drives preview and both export formats.

**Tech Stack:** Swift 6 compiler in Swift 5 language mode, SwiftUI/AppKit, ScreenCaptureKit, AVFoundation, CoreImage, ImageIO, XCTest; no third-party runtime dependencies.

**Spec:** `docs/superpowers/specs/2026-09-22-mac-recorder-design.md`

## Global Constraints

- 首版暂定 macOS 15+，优先在当前 Apple Silicon 机器验证；Intel Mac 不承诺未经验证的兼容性。
- Windows 后续考虑。
- 分享通过本地文件完成。
- 原始录屏保持不变，关闭后可以重新打开工程继续编辑。
- 默认 30 fps，目标长边最多 3840 像素且不放大原始源。
- MP4：H.264 视频、有麦克风时使用 AAC 音频；30 fps。
- GIF：无声音、循环播放；长边 640/960/1280 像素，10/15/20 fps，默认 960 像素与 15 fps。
- 不改动只读的 sources。产品放在独立子目录 `DemoRecorder/`，在那里初始化 Git，不把镜像父目录变为代码仓库。
- No cloud services, system audio, camera, subtitles, decorative backgrounds, recording pause, or keyboard-content logging.
- No formal distribution claim until Developer ID signing, notarization, and installation on another Mac have been verified.

## Review Focus

1. Source window changes position or size mid-capture: invalidate stale mapping and keep pointer events aligned (Task 2).
2. A cut removes the middle of a zoom animation: the new segment must start with its correct source-time camera state (Tasks 1 and 3).
3. Out-of-range or non-finite saved metadata: reject invalid geometry/timing before rendering (Task 1).
4. Destination exists or export is cancelled: preserve existing output and project; remove only job-owned temporary files (Task 4).
5. Permission denial or capture failure during startup: restore usable idle state and release every event monitor (Tasks 2 and 5).

## File map

All product paths below are relative to `DemoRecorder/`.

- `Package.swift`: macOS 15 core library, app executable, integration executable, and core test target.
- `Sources/RecorderCore/Project.swift`: Codable models and validation.
- `Sources/RecorderCore/EditTimeline.swift`: source/output time mapping and edit history.
- `Sources/RecorderCore/AutoZoom.swift`: click clustering and camera evaluation.
- `Sources/RecorderCore/PointerMapping.swift`: display/window coordinate transforms.
- `Sources/RecorderApp/CaptureService.swift`: capture lifecycle and media writing.
- `Sources/RecorderApp/PointerRecorder.swift`: event monitoring and geometry snapshots.
- `Sources/RecorderApp/ProjectStore.swift`: package persistence and recovery.
- `Sources/RecorderApp/MediaRenderer.swift`: shared composition and crop rendering.
- `Sources/RecorderApp/ExportService.swift`: MP4/GIF jobs.
- `Sources/RecorderApp/AppModel.swift`: main-actor state and user actions.
- `Sources/RecorderApp/DemoRecorderApp.swift`, `LibraryView.swift`, `CaptureView.swift`, `EditorView.swift`, `ExportView.swift`: UI.
- `Sources/MediaVerification/main.swift`: generated media integration checks.
- `Tests/RecorderCoreTests/{TimelineTests,ZoomTests,MappingTests,ProjectTests}.swift`: deterministic behavior tests.
- `Resources/Info.plist`, `scripts/build-app.sh`: app bundle and development signing.
- `README.md`, `VALIDATION.md`: operation, packaging, evidence, and unverified cases.

## Task 1: Editable project, timeline, and camera core

**Consumes:** Foundation values only.

**Produces:** Codable `TimeSpan(start: Double, end: Double)`, `PointerSample(time: Double, x: Double, y: Double, clicked: Bool)`, `ZoomSegment(start: Double, end: Double, centerX: Double, centerY: Double, scale: Double, manual: Bool)`, `CameraState(centerX: Double, centerY: Double, scale: Double)`, `Project(version: Int, duration: Double, sourceRelativePath: String, kept: [TimeSpan], zooms: [ZoomSegment])`.

Public core interfaces:

```swift
struct EditTimeline {
    var kept: [TimeSpan]
    var duration: Double { kept.reduce(0) { $0 + $1.end - $1.start } }
    func sourceTime(at outputTime: Double) -> Double?
    mutating func delete(outputRange: TimeSpan)
    mutating func retain(outputRange: TimeSpan)
}
enum AutoZoomPlanner {
    static func plan(samples: [PointerSample], duration: Double) -> [ZoomSegment]
}
enum CameraEvaluator {
    static func evaluate(time: Double, segments: [ZoomSegment], samples: [PointerSample]) -> CameraState
}
```

- [ ] Create Swift package and failing tests before implementation. Pin deletion with this example:

```swift
func testDeleteMiddlePreservesSourceTime() {
    var timeline = EditTimeline(kept: [TimeSpan(start: 0, end: 10)])
    timeline.delete(outputRange: TimeSpan(start: 3, end: 7))
    XCTAssertEqual(timeline.duration, 6, accuracy: 0.0001)
    XCTAssertEqual(timeline.sourceTime(at: 3.5)!, 7.5, accuracy: 0.0001)
}
```

- [ ] Run `swift test --filter TimelineTests`; expect failure from missing implementation, not an unrelated toolchain failure.
- [ ] Implement half-open interval mapping; clamp edit bounds, reject NaN/infinity, discard zero-length intervals, reject empty export. Snapshot the entire editable metadata for undo/redo so cuts and camera edits share history.
- [ ] Add click-planner tests: no clicks returns no zooms; clicks at 1.0 and 1.5 seconds merge; source-boundary clicks produce valid clipped intervals; all normalized crop edges remain within 0...1. Implement 1.8× default, 1.5-second clustering, 0.25-second lead, 0.35-second entry, 1.2-second hold, and 0.45-second exit using smoothstep `u*u*(3-2*u)`. Clamp entry/exit when intervals are short; constrain center by half viewport size.
- [ ] Add project decode tests for invalid version, absolute/traversal media paths, inverted spans, non-finite timing, and out-of-range zoom. Implement explicit validation with readable errors.
- [ ] Run all core tests. Commit the tested core in the product repository.

## Task 2: Actual capture, pointer alignment, and recoverable projects

**Consumes:** Task 1 Codable project and event models.

**Produces:** `@MainActor CaptureService.start(source: CaptureSource, microphone: Bool, destination: URL) async throws`, `stop() async throws -> CapturedRecording`; `CapturedRecording` contains movie URL, duration and pointer samples. `ProjectStore.create(from:)`, `save(_:)`, and `open(_:)` own package persistence.

- [ ] Add coordinate tests before platform implementation. For display rect (-1920,0,1920,1080), point (-960,540) maps to (0.5,0.5). Test upper-left versus lower-left conversion explicitly. A point outside the selected source returns nil. A changed window frame must use its current snapshot, and invalid snapshots return nil.
- [ ] Implement `PointerMapping.normalize(point:contentRect:) -> CGPoint?`; establish one top-left convention for stored geometry, convert AppKit global coordinates once, and use recorded display bounds rather than main-screen-only assumptions.
- [ ] Implement capture around ScreenCaptureKit stream samples and AVAssetWriter. Start the writer session on the first video timestamp, align microphone timestamps to that same clock, and finish after capture stops. Guard stream callbacks against writer teardown. Derive actual source dimensions, cap long edge, and enforce even output sizes.
- [ ] Implement PointerRecorder with local/global mouse-click monitors and 60 Hz position sampling. Use a monotonic host clock mapped to media time, current capture geometry, and events only inside the selected source. Do not create keyboard monitors. Remove timers and monitors in all stop/error paths.
- [ ] Implement project-package creation with relative paths and an in-progress marker. Atomically save metadata to a sibling temporary file then replace it. On open, validate paths and media readability; show recoverable incomplete recordings without deleting originals.
- [ ] Compile the platform target. Exercise real display and window capture, microphone enabled/disabled, denied permission, and selected window closure. If system permission requires user action, report that exact blocked test and continue independent tests.
- [ ] Save capture evidence and commit. Do not describe unperformed permission/multi-monitor tests as passing.

## Task 3: Shared preview rendering and functional editor

**Consumes:** `Project`, `EditTimeline`, `CameraEvaluator` and source media.

**Produces:** `MediaRenderer.makeComposition(project:sourceURL:) async throws -> RenderedMedia`, where `RenderedMedia` owns an `AVComposition`, `AVVideoComposition`, output duration and render size.

- [ ] Write a cut/zoom regression: retained source spans [0,2) and [6,8), camera at output 2.25 seconds must equal source 6.25 seconds, not 2.25 seconds.
- [ ] Build composition by inserting retained video/audio source ranges sequentially. The composition-to-source map must be the same EditTimeline used by camera evaluation. Add at most 5 ms audio fades bounded by segment length to reduce cut clicks.
- [ ] Implement a CoreImage-backed AV video compositor or composition filter using source-time camera state. Render crop then scale to fixed output size; handle source preferred transforms. Use an immutable render snapshot across asynchronous callbacks.
- [ ] Implement editor preview with AVPlayerItem using that exact composition. Playback position and selection use output time; zoom metadata uses source time. Rebuild after committed edits, pause before rebuilding, and clamp playback position.
- [ ] Add a real timeline with thumbnail cache, playhead, selection handles, retain/delete controls, undo/redo, and zoom-segment selection. Side panel edits center, scale, and duration; validate conflicts before applying. Include “disable automatic zoom”, manual segment creation/deletion, and regeneration confirmation if manual edits exist.
- [ ] Generate a known moving-marker clip and inspect preview at times before, inside, and after zoom and a hard cut. Check no interpolation across deleted intervals. Commit preview/editor behavior.

## Task 4: MP4 and GIF export with cancellation

**Consumes:** immutable Project snapshot and `RenderedMedia`.

**Produces:** `ExportService.export(project:sourceURL:settings:destination:progress:) async throws`, cancellable through task cancellation. `ExportSettings` stores format, output sizing, GIF fps and optional selected output interval.

- [ ] Add a media verification executable generating a 4-second clip with timestamp markers and optional deterministic audio. Export after removing [1,2); expected output is 3 seconds with the correct post-cut marker and camera region.
- [ ] Encode MP4 as H.264/AAC with shared video composition, 30 fps and aspect-preserving even dimensions. Support 720p, 1080p and source dimensions without upscaling. Poll or observe job progress and forward cancellation.
- [ ] Encode GIF with ImageIO from the same composition. Sample at selected 10/15/20 fps and long edge 640/960/1280, set loop count to zero, and use bounded autorelease pools per frame. Default 960/15. Check cancellation at each frame and before destination replacement.
- [ ] Write exports to unique job-owned sibling temporary files; only replace destination after success. Test cancellation preserves a preexisting sentinel destination:

```swift
let sentinel = Data("existing export".utf8)
try sentinel.write(to: destination)
// Start the real export task, cancel it before finalization, await cancellation.
XCTAssertEqual(try Data(contentsOf: destination), sentinel)
```

- [ ] Decode resulting files to verify codec, audio presence, dimensions and duration. MP4 duration tolerance is 1/30 second, GIF tolerance is one configured frame. Compare known marker crop at representative times; verify microphone/audio synchronization within 100 ms using the deterministic fixture.
- [ ] Show long-GIF size guidance without claiming exact predicted size. Export selected range only when explicitly selected. Commit after real encoded files pass verification.

## Task 5: App shell, packaging, and end-to-end delivery

**Consumes:** all preceding services and views.

**Produces:** `dist/Demo Recorder.app`, user instructions and a truthful validation record.

- [ ] Implement AppModel with idle/preparing/recording/stopping/editing/exporting states. Ensure failure resets state; prevent double start/stop and export of an empty timeline. Use a recording-generation token so late callbacks cannot alter a newer session.
- [ ] Implement Chinese library/capture/export screens, recent-project persistence, open/save panels, microphone selection, countdown and menu-bar stop action. Use native readable controls, keyboard playback/undo, clear disabled states and error recovery actions.
- [ ] Add Info.plist microphone/screen usage descriptions, stable bundle ID, macOS 15 deployment target and app icon fallback. Build with `swift build -c release`, copy executable/resources into a standard app bundle and ad-hoc sign for local development. Never claim ad-hoc signing substitutes for Developer ID notarization.
- [ ] Test repeated start/stop, permission refusal and retry, export failure/retry, project reopen, moved project package, source loss, and cancel during export. Verify no listener or active recording remains after closing capture.
- [ ] Run `swift test`, build release app and run media verification. Perform a 10-minute recording if recording permission is available, inspect memory trend, reopen and export the result. Use UI screenshots to check legibility and actual edit/export controls.
- [ ] Record each result in VALIDATION.md as PASS, FAIL or NOT RUN with reason; include multi-monitor, window move/resize, microphone, negative-origin display, and second-Mac installation separately. Document launch, permission setup, recording/edit/export instructions, artifacts and signing limitations in README.md.
- [ ] Review implementation against every spec section; fix failures before claiming completion. Commit finished work and present the app path, source location and remaining external validation requirements.

## Execution and plan self-review

Recommended execution is native in the current task: capture, source-time mapping and composition are tightly coupled and benefit from one owner. No external services or credentials are needed for core implementation. OS capture consent and Developer ID distribution remain external actions when actually reached.

Coverage: spec sections 1–3 map to Tasks 2/3/5; 4 to Task 2; 5–6 to Tasks 1/3; 7 to Task 4; 8–9 to Tasks 1/2/5; 10–11 to Tasks 4/5. Camera evaluation is shared rather than duplicated. All review-focus conditions have owning tests or explicitly required device checks. This is a plan, not evidence that any feature is implemented.
