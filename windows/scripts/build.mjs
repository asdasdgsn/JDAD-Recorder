import { build } from "esbuild";
import { mkdir, copyFile } from "node:fs/promises";
await mkdir("dist/renderer", { recursive: true });
await mkdir("dist/region", { recursive: true });
await Promise.all([
  build({
    entryPoints: ["src/main/index.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    target: "node22",
    outfile: "dist/main.cjs",
    external: ["electron", "koffi", "uiohook-napi"],
    sourcemap: true,
  }),
  build({
    entryPoints: ["src/preload.ts"],
    bundle: true,
    platform: "node",
    format: "cjs",
    target: "node22",
    outfile: "dist/preload.cjs",
    external: ["electron"],
  }),
  build({
    entryPoints: ["src/renderer/index.ts"],
    bundle: true,
    platform: "browser",
    format: "esm",
    target: "chrome130",
    outfile: "dist/renderer/renderer.js",
    sourcemap: true,
  }),
  build({
    entryPoints: ["src/region/index.ts"],
    bundle: true,
    platform: "browser",
    format: "esm",
    target: "chrome130",
    outfile: "dist/region/region.js",
  }),
]);
for (const [source, destination] of [
  ["src/renderer/index.html", "dist/renderer/index.html"],
  ["src/renderer/styles.css", "dist/renderer/styles.css"],
  ["src/region/index.html", "dist/region/index.html"],
  ["src/region/region.css", "dist/region/region.css"],
])
  await copyFile(source, destination);
