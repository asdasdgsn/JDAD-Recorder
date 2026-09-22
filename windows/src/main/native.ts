import { createRequire } from "node:module";
import type { Rect, Sample } from "../shared/types";
const requireNative = createRequire(__filename);
let api: any;
function windowsAPI() {
  if (process.platform !== "win32") return null;
  if (!api) {
    const koffi = requireNative("koffi");
    const user = koffi.load("user32.dll");
    const dwm = koffi.load("dwmapi.dll");
    const rect = koffi.struct("JDAD_RECT", {
      left: "long",
      top: "long",
      right: "long",
      bottom: "long",
    });
    const point = koffi.struct("JDAD_POINT", { x: "long", y: "long" });
    api = {
      bounds: dwm.func(
        "long DwmGetWindowAttribute(uintptr_t hwnd, uint32_t attr, _Out_ void *value, uint32_t size)",
      ),
      rect,
      point,
      cursor: user.func("bool GetCursorPos(_Out_ JDAD_POINT *point)"),
      valid: user.func("bool IsWindow(uintptr_t hwnd)"),
      minimized: user.func("bool IsIconic(uintptr_t hwnd)"),
    };
  }
  return api;
}
export function windowBounds(id: string): Rect | null {
  try {
    const a = windowsAPI();
    const match = /^window:(\d+):/.exec(id);
    if (!a || !match) return null;
    const hwnd = BigInt(match[1]);
    if (!a.valid(hwnd) || a.minimized(hwnd)) return null;
    const out = Buffer.alloc(16);
    if (a.bounds(hwnd, 9, out, 16) !== 0) return null;
    const x = out.readInt32LE(0),
      y = out.readInt32LE(4),
      right = out.readInt32LE(8),
      bottom = out.readInt32LE(12);
    return right > x && bottom > y
      ? { x, y, width: right - x, height: bottom - y }
      : null;
  } catch {
    return null;
  }
}
export function trackPointer(
  getBounds: () => Rect | null,
  region: Rect | undefined,
  epoch: number,
  onSample: (sample: Sample) => void,
): { stop: () => void; warnings: string[] } {
  if (process.platform !== "win32")
    return {
      stop: () => {},
      warnings: ["当前是开发预览环境；鼠标自动聚焦需要在 Windows 上验证。"],
    };
  try {
    const a = windowsAPI();
    const hook = requireNative("uiohook-napi").uIOhook;
    const start = performance.now();
    const offset = Math.max(0, Math.min(2, (Date.now() - epoch) / 1000));
    let last = -1;
    const collect = (clicked: boolean) => {
      const time = (performance.now() - start) / 1000 + offset;
      if (!clicked && time - last < 1 / 30) return;
      last = time;
      const b = getBounds();
      if (!b) return;
      const p = { x: 0, y: 0 };
      if (!a.cursor(p)) return;
      let x = (p.x - b.x) / b.width,
        y = (p.y - b.y) / b.height;
      if (region) {
        x = (x - region.x) / region.width;
        y = (y - region.y) / region.height;
      }
      if (x < 0 || x > 1 || y < 0 || y > 1) return;
      onSample({ time, x, y, clicked });
    };
    const move = () => collect(false),
      click = () => collect(true);
    hook.on("mousemove", move);
    hook.on("mousedown", click);
    try {
      hook.start();
    } catch (e) {
      hook.off("mousemove", move);
      hook.off("mousedown", click);
      throw e;
    }
    let stopped = false;
    return {
      stop: () => {
        if (stopped) return;
        stopped = true;
        hook.off("mousemove", move);
        hook.off("mousedown", click);
        try {
          hook.stop();
        } catch {
          /* Stream finalization must still close the file. */
        }
      },
      warnings: [],
    };
  } catch {
    return {
      stop: () => {},
      warnings: ["鼠标跟踪未能启动，本次录制可正常剪辑，也可以手动添加聚焦。"],
    };
  }
}
