# JDAD Recorder Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Implement the approved Windows recorder/editor and produce an honest, verified Windows x64 distribution artifact.
**Architecture:** Electron owns capture, safe filesystem IPC and application lifecycle. A TypeScript core owns all editing and camera math; renderer and FFmpeg exporter consume the same camera states. Windows mouse hooks supply real events.
**Tech Stack:** Electron, TypeScript, vanilla DOM/CSS, uiohook-napi, koffi, FFmpeg, electron-builder, Node test runner.
**Spec:** ../specs/2026-09-22-windows-recorder-design.md

## Global Constraints
- Windows 11, Intel/AMD x64; Chinese UI, JDAD Recorder branding.
- Optional microphone, off by default; no keyboard content collection.
- Local files; no upload/publish; Mac application unchanged.
- MP4 H.264/AAC and GIF; original media preserved; cancel never replaces destination.
- Sidebar URL exactly https://jdauto.joyapp.jd.com/ .
- Real Windows capture/installer execution is reported NOT RUN unless actually exercised on Windows.

## Review Focus
- Reordered source intervals must preserve zoom and audio timing (core/media tests).
- Malformed metadata and filesystem traversal must fail before reading/writing external files (store tests).
- Delayed chunks and double stop must not truncate recordings (serialized capture writes/finalize tests).
- Negative display origins, mixed DPI and out-of-region clicks must not move camera incorrectly (core tests plus Windows acceptance).
- Export cancellation must leave existing destination intact (actual media test).

## Interfaces and files
All code under windows/. Parent owns project setup, src/shared/types.ts, src/main/* excluding media.ts, src/preload.ts and integration. Core task owns src/core/index.ts and tests/core.test.ts. Media task owns src/main/media.ts, scripts/fetch-media.mjs and tests/media.test.ts. Renderer task owns src/renderer/* and src/region/* after contracts exist.

```ts
type Span = {start:number;end:number};
type Rect = {x:number;y:number;width:number;height:number};
type Sample = {time:number;x:number;y:number;clicked:boolean};
type Zoom = Span & {id:string;centerX:number;centerY:number;scale:number;manual:boolean;animationRange?:Span};
type Project = {version:1;id:string;name:string;source:string;duration:number;width:number;height:number;hasAudio:boolean;kept:Span[];zooms:Zoom[];samples:Sample[];autoZoom:boolean};
type Camera = {centerX:number;centerY:number;scale:number};
type ExportSettings = {format:'mp4'|'gif';longEdge:number;fps:number;selection?:Span};
// Core functions are pure and return new arrays/project objects.
// duration(kept), boundaries(kept), sourceTime(kept,time), split(kept,time), moveClip(kept,from,boundary), selectRange(kept,range), deleteRange(kept,range)
// planZooms(samples,duration), cameraAt(project,sourceTime), resizeZoom(project,id,clipIndex,edge,outputTime), snap(time,targets,tolerance), validateProject(project)
// Media: probeMedia(path):Promise<{duration,width,height,hasAudio}>
// exportMedia(project,sourcePath,destination,settings,signal,onProgress):Promise<void>
```

## Task 1 — core behavior and project contracts
- [x] Write core tests before implementation: `assert.deepEqual(split([{start:2,end:6}],1),[{start:2,end:3},{start:3,end:6}])`; reordered mapping, span edits, undo via immutable snapshots, nonfinite/malformed metadata, safe relative source, clipped focus envelope and negative-origin pointer normalization.
- [x] Run `npm test -- --test-name-pattern=core` or named test file; verify missing API failure.
- [x] Implement pure functions, frame rounding, clamp all camera crops to source. Export exact contract names.
- [x] Run core tests; review implementation before integrating capture/export.

## Task 2 — actual media export
- [x] Fixture with red/blue halves and audio pulses. Assert reordered duration, colors, zoom center, GIF frames, and unchanged destination after cancellation.
- [x] Fetch pinned FFmpeg/ffprobe binaries for host and Windows x64, record source/checksum/license; no fake binaries or shell interpolation.
- [x] Build concat/crop/scale camera pipeline from the shared core. Stream progress; abort process and clean only its own temporary files. Output first to a same-directory temporary file then replace successful destination.
- [x] Run true encode/decode tests on host. Include packaged Windows binary presence/architecture checks.

## Task 3 — Electron shell, persistence and recording
- [x] Create package/TypeScript/esbuild scripts and bounded preload API. IPC allow only app renderer, selected source IDs and active project token.
- [x] Store tests use temporary dirs: reject `../outside.mov`; save/open roundtrip; resolve real paths before exporting. Capture chunk writes serialize; finalize waits queue, handles duplicate stop.
- [x] Use desktopCapturer and getDisplayMedia handler. Renderer records WebM chunks every second; optional microphone track; region canvas crop uses normalized display rectangle. Main writes append-only source and finalizes metadata via probe.
- [x] Mouse hook runs only during recording; use Windows physical display/window coordinates, frame/region normalization and monotonic-relative timestamps. Unavailable hook produces visible warning, no fabricated clicks.
- [x] Hide own capture controls when recording; tray stop; cleanup on capture failure, source ended and quit.

## Task 4 — usable editor and region overlay
- [x] Implement responsive Chinese library/recorder/editor with exact JDAD branding/sidebar link.
- [x] Timeline clip lanes, focus bars, split Ctrl+B, move by pointer with insertion boundary, selection handles, snap toggle, zoom, delete/retain, undo/redo.
- [x] Video/canvas preview maps output time to source intervals, cameraAt used per frame; avoid interpolating across cuts.
- [x] Focus dialog shows source frame with draggable crop and live output; commit once or cancel.
- [x] Region overlay supports draw/move/resize, Enter/Escape and excludes its own window before recording. Export modal and progress/cancel.
- [x] Build and inspect UI; report platform-specific interaction tests separately.

## Task 5 — integration and delivery
- [x] Typecheck, unit tests, actual media integration suite, production build.
- [x] Fresh read-only review; fix demonstrated important issues and rerun affected checks.
- [x] electron-builder Windows x64 NSIS/zip with native modules and media executables included; no remote publication. Inspect archive and PE metadata; if installer toolchain unavailable, explicitly report actual artifact and remaining blocker.
- [x] README, validation record, license notices, Windows acceptance checklist; local commit.

## Execution ruling
The user approved the Windows design and asked to continue, with an established preference for direct development. Proceed through this plan without another permission round. Separate independent implementation modules after the shared contracts are written; parent integrates and reviews.

## Verification outcome
All implementation and packaging steps completed. 11 tests, strict typecheck and production build pass. Windows x64 NSIS + ZIP produced and inspected; Windows runtime acceptance remains NOT RUN, explicitly recorded in windows/VALIDATION.md. Independent review fixes are recorded there. Local macOS UI preview checked recorder/library/import/editor/focus dialog only.
