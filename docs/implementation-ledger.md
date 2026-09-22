# SDD ledger — plan: docs/plan.md
Ruling: New product uses its own repository on feature/mac-recorder, as approved in the plan. No preexisting product branch or files require a second worktree.
Ruling: RecorderMedia is a library target so integration tests can exercise real media composition/export without launching UI. App and tests consume the same implementation.
Preflight: Tasks 1→2 share Project and pointer sample models; Tasks 1→3 share source-time mapping; Tasks 3→4 share rendered composition; Tasks 2/3/4→5 share lifecycle. No conflicting types.
Task 1 started: missing core API produces expected compile failures in behavior tests.
Tasks 1–4 implementation present. Core and real generated-media tests: 9 PASS (2026-09-22 09:16). Test target discovery initially reused cached package graph: media RED command ran only core tests, so no claim of full media TDD; integration suite subsequently built and ran against real media. Core RED→GREEN verified.
Ruling: App import is included as a recovery and validation path for existing videos; no automatic mouse track inferred for imported assets.
Ruling: Timeline thumbnails are in-memory disposable preview caches rather than persisted files; project integrity does not depend on them.
Task 5 in progress: app packaging, native UI inspection, expanded lifecycle/audio cases and final review remain.
Final review: fresh read-only reviewer identified five Important findings; no Critical/Minor findings.
Final fixes: Retina points→pixels, CompletionGate-based quit waiting, bounded project duration plus safe formatting, canonical export path validation, CaptureAttempt generations plus startup error buffering. Added corresponding tests; suite 21/21 PASS.
Additional verification: actual audio pulse alignment; in-progress GIF cancellation cleanup; 10-minute synthetic pointer sequence; real UI crop/undo/GIF export and final app reopen.
Ruling: Cannot complete real screen/microphone acceptance while TCC is denied. All hardware-dependent acceptance checks remain explicitly NOT RUN in VALIDATION.md; no bypass or silent grant. No claim that 10-minute synthetic track test equals a real capture.
Ruling: Preserve standalone new repository feature/mac-recorder as local deliverable. There is no original base branch or remote to merge/push; a Git integration choice is inapplicable to this new local product.
Ruling: Retain fixed .app and ZIP for user testing; Developer ID and second-Mac validation require external credentials/device and are not claimed complete.
Task 5 implementation and local artifact verification finished; real-capture acceptance pending user-provided OS permission.

Approved bounded extension (v0.2): resize focus bars, split at playhead, reorder clips by drag, gapless insertion and snapping. User approved in chat; no further design gate required.
Implementation: ordered source spans, frame-aligned splits, snapshot-based drag commits, local focus fragments with preserved animation envelopes, Cmd-B and synchronized right-clip selection, v2 persistence compatible with v1 reads.
Regression evidence: automatic follow interpolation immediately before a cut failed before extending fragment track sampling through the original envelope; correction passes. Full suite now 31 tests including actual reordered MP4/GIF pixel checks and audio pulse alignment.
Fresh independent read-only review: no blockers; P3 split selection mismatch corrected. Native gesture end-to-end remains unverified because user input interrupted the attempted automation. Do not claim this as passed.
Delivery: build separately into dist/v0.2 to preserve the running app and the user's active project. No user project or source recording reset.

v0.3 bounded visual focus request: followed existing direct-development authorization. Replaced XY sliders with a source-frame positioning sheet, normalized crop geometry, live magnified result, explicit apply/cancel and existing undo integration. No new persistence schema.
TDD: four coordinate tests first failed on missing FocusFraming; implementation passes all 35 tests. Fresh read-only review found no blockers. Native UI test stopped after external user input while opening the isolated generated fixture; no claim of full gesture verification. Build packaged separately from active user app.

v0.3.1 permission bug: observed ON toggle alongside explicit TCC code-requirement mismatch, traced to ad-hoc signing across builds and multiple launch paths. Updated packaging to stable local certificate identity, fail on ad-hoc and ambiguous identity; installed at canonical /Applications path with backup. Added denial-specific guidance and stale-list clearing. RED signing check + missing guidance tests -> GREEN, 37 tests. Cross-version signature requirement equality verified. Fresh read-only review found no blockers. Live enumeration remains denied pending user migration of old OS consent; no automatic privacy grants/reset.

v0.4 bounded extension: region mode on existing display capture. Native live transparent selection panel supports draw/move/corner-resize, Enter confirm, Escape cancel. Capture uses display-local SCStreamConfiguration.sourceRect and region-sized encoder; pointer normalization uses the corresponding global rectangle. Busy/quit integration cancels outstanding selection; switching displays invalidates old bounds.
Seven geometry tests, 44 total pass. Fresh read-only reviewer found two rounding defects; corrected and regression-tested. Native source enumeration, entry flow and Escape confirmed. Full capture remains NOT RUN because native tool cannot target drag on full-screen overlay (windowNotFoundAtPosition). No claim of region recording runtime acceptance. Installed and signed at stable /Applications path; permissions survived this update.
