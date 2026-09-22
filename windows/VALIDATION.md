# Windows 0.1.0 validation — 2026-09-22

## Completed

- TypeScript strict typecheck passed.
- Production renderer, region overlay, sandboxed preload and main process bundles built successfully.
- All **11 tests passed**, with final downloaded host media tools: six core tests, two media tests, three persistence tests. Tests cover source mapping after reordering, immutable edits, zoom animation fragments, disabled automatic zoom, negative display origins, bounds validation, ordered recording writes, save roundtrip, traversal/symlink rejection, real video/audio reordering, animated crop, rotated video import, GIF frames, WebM remux and cancellation preserving an existing destination.
- Additional mocked recorder lifecycle checks passed for repeated explicit stop, an already-inactive encoder error, and automatic stop.
- Independent reviews found and fixed recovery path containment, partial recovery destination collision, optional native load failure, recording handle close on sync failure, switching-project autosave ordering, quit intent, inactive-recorder errors, timeline alignment and imported-video rotation.
- Electron development app opened on macOS. Recorder source picker, library, import of generated six-second video, editor video preview and visual focus dialog were inspected through the application UI. This is not Windows capture verification.
- NSIS installer and portable ZIP generated for Windows x64. Main executable resources report JDAD Recorder / JDAD / 0.1.0 with the application icon. Installer and app are unsigned.
- Packaged main/preload/renderer/region bundles match the final build. Packaged FFmpeg/ffprobe match upstream-verified Windows assets. Both mouse/coordinate native modules are present as AMD64 PE binaries outside ASAR. Only Windows media tools are included; the nonfree Mac development tools are excluded.

## Windows acceptance still required

No Windows host was available. These are **NOT RUN**, not passing checks:

- Install, launch and uninstall on Windows 11 x64; user account without administrator rights.
- Screen, window and region recording, including source closed/minimized during recording.
- Mixed 100%/150%/200% display scaling, display to the left/above primary, window movement/resizing, click-to-focus alignment.
- No microphone, allowed microphone and denied microphone; source-ended and encoder-error cleanup.
- Recording with the editor hidden, tray Stop/Exit, normal window close and crash recovery.
- Manual timeline split/reorder, range/focus dragging, playback and actual MP4/GIF export on Windows.
- Large/long recording performance and disk-full behavior on Windows.

This is a local team preview, not a signed, Windows-certified production release. Checksums in `release/SHA256SUMS.txt` identify the delivered files. See `THIRD-PARTY-MEDIA.md` for media licensing/source provenance and distribution requirements.
