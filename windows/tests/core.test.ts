import { test } from "node:test";
import assert from "node:assert/strict";
import {
  duration,
  boundaries,
  sourceTime,
  split,
  moveClip,
  selectRange,
  deleteRange,
  planZooms,
  cameraAt,
  resizeZoom,
  snap,
  validateProject,
  normalizePointer,
} from "../src/core/index.js";
import type { Project } from "../src/shared/types.js";
const project = (): Project => ({
  version: 1,
  id: "test",
  name: "测试",
  source: "media/source.webm",
  duration: 10,
  width: 1920,
  height: 1080,
  hasAudio: false,
  kept: [{ start: 0, end: 10 }],
  zooms: [],
  samples: [],
  autoZoom: true,
});
test("core source spans preserve reorder and immutable edits", () => {
  const s = [{ start: 2, end: 6 }];
  assert.deepEqual(split(s, 1), [
    { start: 2, end: 3 },
    { start: 3, end: 6 },
  ]);
  assert.deepEqual(s, [{ start: 2, end: 6 }]);
  const a = [
    { start: 0, end: 2 },
    { start: 5, end: 8 },
  ];
  const b = moveClip(a, 0, 2);
  assert.deepEqual(b, [a[1], a[0]]);
  assert.equal(duration(b), 5);
  assert.deepEqual(boundaries(b), [0, 3, 5]);
  assert.equal(sourceTime(b, 3), 0);
  assert.equal(sourceTime(b, 5), 2);
  assert.equal(sourceTime(b, -1), null);
  assert.deepEqual(selectRange(b, { start: 2, end: 4 }), [
    { start: 7, end: 8 },
    { start: 0, end: 1 },
  ]);
  assert.deepEqual(deleteRange(b, { start: 2, end: 4 }), [
    { start: 5, end: 7 },
    { start: 1, end: 2 },
  ]);
});
test("core validation rejects corrupt metadata and paths but allows reorder", () => {
  const p = project();
  p.kept = [
    { start: 5, end: 10 },
    { start: 0, end: 5 },
  ];
  validateProject(p);
  for (const patch of [
    { duration: -1 },
    { duration: NaN },
    { version: 2 },
    { source: "../outside.mp4" },
    { source: "media/../a" },
    { source: "media\\a" },
    { source: "C:/media/a" },
    { source: "media/a:stream" },
    {
      kept: [
        { start: 0, end: 7 },
        { start: 6, end: 10 },
      ],
    },
    { samples: [{ time: 0, x: Infinity, y: 0, clicked: true }] },
  ])
    assert.throws(() => validateProject({ ...p, ...patch }));
});
test("core camera crop stays in bounds and preserves untouched animation envelopes", () => {
  const p = project();
  p.kept = [
    { start: 0, end: 5 },
    { start: 5, end: 10 },
  ];
  p.zooms = [
    {
      id: "z",
      start: 2,
      end: 8,
      centerX: 0,
      centerY: 1,
      scale: 3,
      manual: true,
    },
  ];
  const before = cameraAt(p, 6);
  const q = resizeZoom(p, "z", 0, "end", 4);
  assert.equal(p.zooms[0].end, 8);
  assert.deepEqual(cameraAt(q, 6), before);
  assert.deepEqual(q.zooms.find((z) => z.start === 5)?.animationRange, {
    start: 2,
    end: 8,
  });
  for (let t = 0; t < 10; t += 0.1) {
    const c = cameraAt(q, t);
    assert.ok(c.centerX - 0.5 / c.scale >= -1e-9);
    assert.ok(c.centerY + 0.5 / c.scale <= 1 + 1e-9);
  }
  validateProject(q);
});
test("core clicks, snap, negative display origin and cropped region", () => {
  assert.deepEqual(
    normalizePointer(
      { x: -1500, y: 300 },
      { x: -1920, y: 0, width: 1920, height: 1080 },
    ),
    { x: 420 / 1920, y: 300 / 1080 },
  );
  assert.equal(
    normalizePointer(
      { x: -1900, y: 10 },
      { x: -1920, y: 0, width: 1920, height: 1080 },
      { x: 0.25, y: 0.25, width: 0.5, height: 0.5 },
    ),
    null,
  );
  assert.equal(snap(1.02, [1, 2], 0.05), 1);
  assert.equal(
    planZooms(
      [
        { time: 1, x: 0.5, y: 0.5, clicked: true },
        { time: 2, x: 2, y: 0.5, clicked: true },
      ],
      10,
    ).length,
    1,
  );
});
test("core automatic camera is independent of render order and clip fragment boundaries", () => {
  const p = project();
  p.kept = [
    { start: 0, end: 5 },
    { start: 5, end: 10 },
  ];
  p.zooms = [
    {
      id: "follow",
      start: 1,
      end: 9,
      centerX: 0.3,
      centerY: 0.3,
      scale: 2,
      manual: false,
    },
  ];
  p.samples = [
    { time: 2, x: 0.2, y: 0.3, clicked: true },
    { time: 4, x: 0.8, y: 0.8, clicked: false },
    { time: 6, x: 0.9, y: 0.4, clicked: true },
    { time: 8, x: 0.6, y: 0.5, clicked: false },
  ];
  const expected = cameraAt(p, 6.5);
  cameraAt(p, 8);
  cameraAt(p, 1.5);
  assert.deepEqual(cameraAt(p, 6.5), expected);
  const q = resizeZoom(p, "follow", 0, "start", 2);
  assert.deepEqual(cameraAt(q, 6.5), expected);
  assert.deepEqual(cameraAt({ ...p, autoZoom: false }, 6.5), {
    centerX: 0.5,
    centerY: 0.5,
    scale: 1,
  });
  assert.equal(resizeZoom(p, "follow", 0, "start", 1), p);
});
test("core empty and out of bounds edit ranges have stable behavior", () => {
  assert.equal(sourceTime([], 0), null);
  assert.deepEqual(boundaries([]), [0]);
  const s = [{ start: 3, end: 7 }];
  assert.deepEqual(deleteRange(s, { start: -3, end: -1 }), s);
  assert.deepEqual(deleteRange(s, { start: -3, end: 100 }), []);
  assert.deepEqual(selectRange(s, { start: 100, end: 110 }), []);
  assert.deepEqual(moveClip(s, 5, 0), s);
  assert.deepEqual(split(s, 0), s);
  assert.deepEqual(split(s, 4), s);
});
