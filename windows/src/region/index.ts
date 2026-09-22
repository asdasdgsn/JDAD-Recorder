import type { Rect } from "../shared/types";
const box = document.querySelector<HTMLDivElement>("#selection")!;
let rect: Rect | null = null,
  drag: { x: number; y: number; rect: Rect; mode: string } | null = null;
let extent = { width: innerWidth, height: innerHeight };
window.regionAPI.initial().then((v) => (extent = v));
const clamp = (n: number, max: number) => Math.max(0, Math.min(max, n));
function paint() {
  if (!rect) return;
  box.style.display = "block";
  Object.assign(box.style, {
    left: `${rect.x}px`,
    top: `${rect.y}px`,
    width: `${rect.width}px`,
    height: `${rect.height}px`,
  });
  document.querySelector("#dimensions")!.textContent =
    `${Math.round(rect.width)} × ${Math.round(rect.height)}`;
}
window.addEventListener("pointerdown", (e) => {
  const target = e.target as HTMLElement;
  const mode =
    target.dataset.corner || (target.closest("#selection") ? "move" : "new");
  drag = {
    x: e.clientX,
    y: e.clientY,
    rect: rect
      ? { ...rect }
      : { x: e.clientX, y: e.clientY, width: 0, height: 0 },
    mode,
  };
  if (mode === "new")
    rect = { x: e.clientX, y: e.clientY, width: 0, height: 0 };
  (e.target as HTMLElement).setPointerCapture(e.pointerId);
});
window.addEventListener("pointermove", (e) => {
  if (!drag) return;
  const x = clamp(e.clientX, extent.width),
    y = clamp(e.clientY, extent.height),
    r = drag.rect,
    dx = x - drag.x,
    dy = y - drag.y;
  if (drag.mode === "new")
    rect = {
      x: Math.min(x, drag.x),
      y: Math.min(y, drag.y),
      width: Math.abs(x - drag.x),
      height: Math.abs(y - drag.y),
    };
  else if (drag.mode === "move")
    rect = {
      ...r,
      x: clamp(r.x + dx, extent.width - r.width),
      y: clamp(r.y + dy, extent.height - r.height),
    };
  else {
    let l = r.x,
      t = r.y,
      rr = r.x + r.width,
      b = r.y + r.height;
    if (drag.mode.includes("w")) l = Math.min(x, rr - 32);
    if (drag.mode.includes("e")) rr = Math.max(x, l + 32);
    if (drag.mode.includes("n")) t = Math.min(y, b - 32);
    if (drag.mode.includes("s")) b = Math.max(y, t + 32);
    rect = {
      x: clamp(l, extent.width),
      y: clamp(t, extent.height),
      width: rr - l,
      height: b - t,
    };
  }
  paint();
});
window.addEventListener("pointerup", () => (drag = null));
window.addEventListener("keydown", (e) => {
  if (e.key === "Escape") void window.regionAPI.finish(null);
  if (e.key === "Enter" && rect && rect.width >= 32 && rect.height >= 32)
    void window.regionAPI.finish({
      x: rect.x / extent.width,
      y: rect.y / extent.height,
      width: rect.width / extent.width,
      height: rect.height / extent.height,
    });
});
