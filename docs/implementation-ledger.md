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
