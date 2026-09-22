import { createHash } from "node:crypto";
import { createReadStream, createWriteStream } from "node:fs";
import { chmod, copyFile, mkdir, mkdtemp, rename, rm } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createGunzip } from "node:zlib";
import { pipeline } from "node:stream/promises";
import { spawn } from "node:child_process";

// Digests copied from upstream GitHub release asset metadata, not from the mirror.
// https://github.com/eugeneware/ffmpeg-static/releases/expanded_assets/b6.1.1
const release = "b6.1.1";
const hashes = {
  "darwin-arm64.LICENSE":
    "cb48bf09a11f5fb576cddb0431c8f5ed0a60157a9ec942adffc13907cbe083f2",
  "darwin-arm64.LICENSE.gz":
    "5995e6d7b7fdb371505351fce50b9d6fd4d051f69d3468ed4dd4cbfc14a5b916",
  "darwin-arm64.README":
    "05ba4b92c96605434b1aaae3eedf5a2c280c9607bf78ffca9a5b536d9af2dc6a",
  "darwin-arm64.README.gz":
    "527d4ea64a17e81a72ab57103b3817ee224261b5c07844d5a99af40758315154",
  "ffmpeg-darwin-arm64":
    "a90e3db6a3fd35f6074b013f948b1aa45b31c6375489d39e572bea3f18336584",
  "ffmpeg-darwin-arm64.gz":
    "8923876afa8db5585022d7860ec7e589af192f441c56793971276d450ed3bbfa",
  "ffmpeg-win32-x64":
    "04e1307997530f9cf2fe35cba2ca7e8875ca91da02f89d6c7243df819c94ad00",
  "ffmpeg-win32-x64.gz":
    "8883a3dffbd0a16cf4ef95206ea05283f78908dbfb118f73c83f4951dcc06d77",
  "ffprobe-darwin-arm64":
    "bb2db6f5d8cef919da12fbf592119a987202a8c060a886f3cab091f9cab90b64",
  "ffprobe-darwin-arm64.gz":
    "d986a8ec7b030899fe66a8a288ed809a3543338705a3ce178cfb85869c5d80be",
  "ffprobe-win32-x64":
    "3a7e2dc003dc2cd1472827e4c7c4f056ae1ae0ae7c5bbc580c99b49827351ba4",
  "ffprobe-win32-x64.gz":
    "f309e6223ad89d2fe54bccd420a7709b66fd27540674e92309578ed491a43c8d",
  "win32-x64.LICENSE":
    "8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903",
  "win32-x64.LICENSE.gz":
    "d751d40ef8ba97bf46964ae203bf88e7c0027b5459946ac758403c1bb032523f",
  "win32-x64.README":
    "a636a7183c58006351acbaf35303c0ed85c6e1320fd4e80de453ba6157de6311",
  "win32-x64.README.gz":
    "9910569b1b42c01b91dd03b85abc8472a15b5aa31188e41e9654ae08cc179d07",
};
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const supported = ["darwin-arm64", "win32-x64"];
const requested = process.argv.slice(2);
const targets = requested.length
  ? requested
  : [
      ...new Set([
        "win32-x64",
        ...(process.platform === "darwin" && process.arch === "arm64"
          ? ["darwin-arm64"]
          : []),
      ]),
    ];
if (targets.some((target) => !supported.includes(target)))
  throw new Error("Supported targets: darwin-arm64, win32-x64");
const base =
  process.env.MEDIA_DOWNLOAD_BASE ||
  `https://registry.npmmirror.com/-/binary/ffmpeg-static/${release}`;
async function digest(path) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest("hex");
}
async function check(path, expected) {
  try {
    return (await digest(path)) === expected;
  } catch {
    return false;
  }
}
async function fetchAsset(name, path) {
  await new Promise((accept, reject) => {
    const child = spawn(
      "curl",
      [
        "--fail",
        "--location",
        "--silent",
        "--show-error",
        "--retry",
        "3",
        `${base}/${name}`,
        "--output",
        path,
      ],
      { stdio: "inherit", windowsHide: true },
    );
    child.on("error", reject);
    child.on("close", (code) =>
      code === 0
        ? accept()
        : reject(new Error(`Download failed: ${name} (${code})`)),
    );
  });
  if (!(await check(path, hashes[name])))
    throw new Error(`SHA-256 mismatch: ${name}`);
}
for (const target of targets) {
  const directory = join(root, "vendor", target);
  await mkdir(directory, { recursive: true });
  const staging = await mkdtemp(join(directory, ".fetch-"));
  try {
    const results = await Promise.allSettled(
      ["ffmpeg", "ffprobe"].map(async (tool) => {
        const asset = `${tool}-${target}`,
          output = join(
            directory,
            `${tool}${target.startsWith("win") ? ".exe" : ""}`,
          );
        if (await check(output, hashes[asset])) {
          await chmod(output, 0o755);
          return;
        }
        console.log(`Fetching ${asset} (${release})`);
        const compressed = join(staging, asset + ".gz"),
          raw = join(staging, asset);
        await fetchAsset(asset + ".gz", compressed);
        await pipeline(
          createReadStream(compressed),
          createGunzip(),
          createWriteStream(raw, { flags: "wx" }),
        );
        if (!(await check(raw, hashes[asset])))
          throw new Error(`Binary SHA-256 mismatch: ${asset}`);
        await chmod(raw, 0o755);
        await rename(raw, output);
      }),
    );
    const failed = results.find((result) => result.status === "rejected");
    if (failed) throw failed.reason;
    for (const kind of ["LICENSE", "README"]) {
      const name = `${target}.${kind}`,
        temp = join(staging, name),
        output = join(directory, kind);
      if (await check(output, hashes[name])) continue;
      await fetchAsset(name, temp);
      await rename(temp, output);
    }
    await copyFile(
      join(root, "THIRD-PARTY-MEDIA.md"),
      join(directory, "PROVENANCE.md"),
    );
    console.log(`Verified ${target}`);
  } finally {
    await rm(staging, { recursive: true, force: true });
  }
}
