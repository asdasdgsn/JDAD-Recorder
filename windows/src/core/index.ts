import type {
  Span,
  Rect,
  Sample,
  Zoom,
  Project,
  Camera,
} from "../shared/types.js";
const clamp = (n: number, a: number, b: number) => Math.min(b, Math.max(a, n));
const copy = (s: Span): Span => ({ ...s });
export function duration(spans: Span[]): number {
  return spans.reduce((n, s) => n + s.end - s.start, 0);
}
export function boundaries(spans: Span[]): number[] {
  const out = [0];
  for (const s of spans) out.push(out[out.length - 1] + s.end - s.start);
  return out;
}
export function sourceTime(spans: Span[], time: number): number | null {
  if (!Number.isFinite(time) || time < 0) return null;
  let offset = 0;
  for (let i = 0; i < spans.length; i++) {
    const s = spans[i],
      end = offset + s.end - s.start;
    if (time < end || (i === spans.length - 1 && time === end))
      return s.start + time - offset;
    offset = end;
  }
  return null;
}
export function split(spans: Span[], time: number): Span[] {
  let offset = 0;
  return spans.flatMap((s) => {
    const local = time - offset;
    offset += s.end - s.start;
    return local > 0 && local < s.end - s.start
      ? [
          { start: s.start, end: s.start + local },
          { start: s.start + local, end: s.end },
        ]
      : [copy(s)];
  });
}
export function moveClip(
  spans: Span[],
  from: number,
  boundary: number,
): Span[] {
  const out = spans.map(copy);
  if (
    !Number.isInteger(from) ||
    from < 0 ||
    from >= out.length ||
    !Number.isInteger(boundary) ||
    boundary < 0 ||
    boundary > out.length
  )
    return out;
  const [clip] = out.splice(from, 1);
  out.splice(boundary > from ? boundary - 1 : boundary, 0, clip);
  return out;
}
export function selectRange(spans: Span[], range: Span): Span[] {
  if (!Number.isFinite(range.start) || !Number.isFinite(range.end)) return [];
  let offset = 0;
  return spans.flatMap((s) => {
    const start = Math.max(0, range.start - offset),
      end = Math.min(s.end - s.start, range.end - offset);
    offset += s.end - s.start;
    return end > start ? [{ start: s.start + start, end: s.start + end }] : [];
  });
}
export function deleteRange(spans: Span[], range: Span): Span[] {
  if (
    !Number.isFinite(range.start) ||
    !Number.isFinite(range.end) ||
    range.end <= range.start
  )
    return spans.map(copy);
  return [
    ...selectRange(spans, { start: 0, end: Math.max(0, range.start) }),
    ...selectRange(spans, {
      start: Math.max(0, range.end),
      end: duration(spans),
    }),
  ];
}
export function snap(
  time: number,
  targets: number[],
  tolerance: number,
): number {
  if (!Number.isFinite(time)) return 0;
  let best: number | undefined;
  for (const target of targets)
    if (
      Number.isFinite(target) &&
      Math.abs(target - time) <= Math.max(0, tolerance) &&
      (best === undefined || Math.abs(target - time) < Math.abs(best - time))
    )
      best = target;
  return best ?? Math.round(time * 30) / 30;
}
export function normalizePointer(
  point: { x: number; y: number },
  bounds: Rect,
  region: Rect = { x: 0, y: 0, width: 1, height: 1 },
): { x: number; y: number } | null {
  if (
    ![
      point.x,
      point.y,
      bounds.x,
      bounds.y,
      bounds.width,
      bounds.height,
      region.x,
      region.y,
      region.width,
      region.height,
    ].every(Number.isFinite) ||
    bounds.width <= 0 ||
    bounds.height <= 0 ||
    region.width <= 0 ||
    region.height <= 0
  )
    return null;
  const x = ((point.x - bounds.x) / bounds.width - region.x) / region.width,
    y = ((point.y - bounds.y) / bounds.height - region.y) / region.height;
  return x >= 0 && x <= 1 && y >= 0 && y <= 1 ? { x, y } : null;
}
export function planZooms(samples: Sample[], length: number): Zoom[] {
  const clicks = samples
    .filter(
      (s) =>
        s.clicked &&
        s.time >= 0 &&
        s.time < length &&
        s.x >= 0 &&
        s.x <= 1 &&
        s.y >= 0 &&
        s.y <= 1,
    )
    .sort((a, b) => a.time - b.time);
  const out: Zoom[] = [];
  for (const c of clicks) {
    const start = Math.max(0, c.time - 0.25),
      end = Math.min(length, c.time + 1.65),
      last = out.at(-1);
    if (last && start <= last.end) last.end = end;
    else
      out.push({
        id: `auto-${out.length}-${c.time}`,
        start,
        end,
        centerX: c.x,
        centerY: c.y,
        scale: 1.8,
        manual: false,
      });
  }
  return out;
}
type Key = { time: number; x: number; y: number };
type Track = { zoom: Zoom; keys: Key[] };
const tracks = new WeakMap<Project, Track[]>();
function upper<T>(list: T[], time: number, key: (v: T) => number): number {
  let lo = 0,
    hi = list.length;
  while (lo < hi) {
    const m = (lo + hi) >>> 1;
    if (key(list[m]) <= time) lo = m + 1;
    else hi = m;
  }
  return lo;
}
function trackFor(p: Project): Track[] {
  const existing = tracks.get(p);
  if (existing) return existing;
  const samples = p.samples
    .filter((s) => s.x >= 0 && s.x <= 1 && s.y >= 0 && s.y <= 1)
    .slice()
    .sort((a, b) => a.time - b.time);
  const result = p.zooms
    .slice()
    .sort((a, b) => a.start - b.start)
    .map((zoom) => {
      const range = zoom.animationRange ?? zoom;
      let x = zoom.centerX,
        y = zoom.centerY,
        last = range.start;
      const keys: Key[] = [{ time: last, x, y }];
      if (!zoom.manual) {
        let i = upper(samples, range.start - Number.EPSILON, (s) => s.time);
        for (; i < samples.length && samples[i].time < range.end; i++) {
          const s = samples[i],
            limit = 0.3 / zoom.scale,
            alpha = 1 - Math.exp(-Math.max(0, s.time - last) / 0.16);
          x += (clamp(x, s.x - limit, s.x + limit) - x) * alpha;
          y += (clamp(y, s.y - limit, s.y + limit) - y) * alpha;
          last = s.time;
          keys.push({ time: last, x, y });
        }
      }
      return { zoom, keys };
    });
  tracks.set(p, result);
  return result;
}
export function cameraAt(project: Project, time: number): Camera {
  const neutral = { centerX: 0.5, centerY: 0.5, scale: 1 };
  if (!Number.isFinite(time)) return neutral;
  const ts = trackFor(project),
    track = ts[upper(ts, time, (t) => t.zoom.start) - 1];
  if (
    !track ||
    time >= track.zoom.end ||
    (!project.autoZoom && !track.zoom.manual)
  )
    return neutral;
  const { zoom: z, keys } = track,
    range = z.animationRange ?? z,
    length = range.end - range.start;
  const smooth = (v: number) => {
    const u = clamp(v, 0, 1);
    return u * u * (3 - 2 * u);
  };
  const amount = Math.min(
    smooth((time - range.start) / Math.min(0.35, length / 2)),
    smooth((range.end - time) / Math.min(0.45, length / 2)),
  );
  const scale = 1 + (clamp(z.scale, 1, 3) - 1) * amount;
  let x = z.centerX,
    y = z.centerY;
  if (!z.manual) {
    const i = upper(keys, time, (k) => k.time),
      a = keys[Math.max(0, i - 1)],
      b = keys[Math.min(keys.length - 1, i)],
      u =
        b.time > a.time ? clamp((time - a.time) / (b.time - a.time), 0, 1) : 0;
    x = a.x + (b.x - a.x) * u;
    y = a.y + (b.y - a.y) * u;
  }
  const half = 0.5 / scale;
  return {
    centerX: clamp(0.5 + (x - 0.5) * amount, half, 1 - half),
    centerY: clamp(0.5 + (y - 0.5) * amount, half, 1 - half),
    scale,
  };
}
export function resizeZoom(
  project: Project,
  id: string,
  clipIndex: number,
  edge: "start" | "end",
  outputTime: number,
): Project {
  const clip = project.kept[clipIndex],
    z = project.zooms.find((z) => z.id === id);
  if (!clip || !z || !Number.isFinite(outputTime)) return project;
  const start = Math.max(z.start, clip.start),
    end = Math.min(z.end, clip.end);
  if (end <= start) return project;
  const other = project.zooms.filter((z) => z.id !== id),
    left = Math.max(
      clip.start,
      ...other.filter((v) => v.end <= start).map((v) => v.end),
    ),
    right = Math.min(
      clip.end,
      ...other.filter((v) => v.start >= end).map((v) => v.start),
    );
  const t = clip.start + outputTime - boundaries(project.kept)[clipIndex],
    minimum = Math.min(1 / 30, end - start);
  const edited: Zoom = { ...z, start, end };
  delete edited.animationRange;
  if (edge === "start") edited.start = clamp(t, left, end - minimum);
  else edited.end = clamp(t, start + minimum, right);
  if (edited.start === start && edited.end === end) return project;
  const envelope = z.animationRange ?? { start: z.start, end: z.end },
    fragments = [edited];
  const unique = (suffix: string) => {
    let id = `${z.id}-${suffix}`;
    while (
      project.zooms.some((v) => v.id === id) ||
      fragments.some((v) => v.id === id)
    )
      id += "-1";
    return id;
  };
  if (z.start < start)
    fragments.push({
      ...z,
      id: unique("before"),
      end: start,
      animationRange: { ...envelope },
    });
  if (z.end > end)
    fragments.push({
      ...z,
      id: unique("after"),
      start: end,
      animationRange: { ...envelope },
    });
  return {
    ...project,
    zooms: [...other, ...fragments].sort((a, b) => a.start - b.start),
  };
}
export function validateProject(value: unknown): asserts value is Project {
  const fail = (): never => {
    throw new Error("工程数据无效或包含不安全的素材路径。");
  };
  const obj = (v: unknown): v is Record<string, unknown> =>
    !!v && typeof v === "object" && !Array.isArray(v);
  const finite = (v: unknown): v is number =>
    typeof v === "number" && Number.isFinite(v);
  const text = (v: unknown) =>
    typeof v === "string" && v.length > 0 && v.length <= 1000;
  if (!obj(value)) fail();
  const p = value as Record<string, any>;
  if (
    p.version !== 1 ||
    !text(p.id) ||
    !/^[a-zA-Z0-9_-]+$/.test(p.id) ||
    !text(p.name) ||
    !finite(p.duration) ||
    p.duration <= 0 ||
    p.duration > 604800 ||
    !Number.isInteger(p.width) ||
    !Number.isInteger(p.height) ||
    p.width < 1 ||
    p.height < 1 ||
    p.width > 32768 ||
    p.height > 32768 ||
    typeof p.hasAudio !== "boolean" ||
    typeof p.autoZoom !== "boolean"
  )
    fail();
  if (
    typeof p.source !== "string" ||
    p.source.length > 1000 ||
    !/^media\/[^\\\x00-\x1f:*?"<>|]+$/.test(p.source) ||
    p.source
      .split("/")
      .some(
        (s: string) =>
          !s ||
          s === "." ||
          s === ".." ||
          /[. ]$/.test(s) ||
          /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(s),
      )
  )
    fail();
  const span = (s: any) =>
    obj(s) &&
    finite(s.start) &&
    finite(s.end) &&
    s.start >= 0 &&
    s.end > s.start &&
    s.end <= p.duration;
  if (
    !Array.isArray(p.kept) ||
    !Array.isArray(p.zooms) ||
    !Array.isArray(p.samples) ||
    p.kept.length > 100000 ||
    p.zooms.length > 100000 ||
    p.samples.length > 10000000
  )
    fail();
  for (const array of [p.kept, p.zooms]) {
    if (!array.every(span)) fail();
    let end = 0;
    for (const s of array
      .slice()
      .sort((a: Span, b: Span) => a.start - b.start)) {
      if (s.start < end) fail();
      end = s.end;
    }
  }
  const ids = new Set<string>();
  for (const z of p.zooms) {
    if (
      !text(z.id) ||
      ids.has(z.id) ||
      ![z.centerX, z.centerY, z.scale].every(finite) ||
      z.centerX < 0 ||
      z.centerX > 1 ||
      z.centerY < 0 ||
      z.centerY > 1 ||
      z.scale < 1 ||
      z.scale > 3 ||
      typeof z.manual !== "boolean"
    )
      fail();
    ids.add(z.id);
    if (
      z.animationRange !== undefined &&
      (!span(z.animationRange) ||
        z.animationRange.start > z.start ||
        z.animationRange.end < z.end)
    )
      fail();
  }
  for (const s of p.samples)
    if (
      !obj(s) ||
      !finite(s.time) ||
      s.time < 0 ||
      s.time > p.duration ||
      !finite(s.x) ||
      !finite(s.y) ||
      s.x < 0 ||
      s.x > 1 ||
      s.y < 0 ||
      s.y > 1 ||
      typeof s.clicked !== "boolean"
    )
      fail();
}
