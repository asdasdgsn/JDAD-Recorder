import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
const expected = {
  "vendor/win32-x64/ffmpeg.exe":
    "04e1307997530f9cf2fe35cba2ca7e8875ca91da02f89d6c7243df819c94ad00",
  "vendor/win32-x64/ffprobe.exe":
    "3a7e2dc003dc2cd1472827e4c7c4f056ae1ae0ae7c5bbc580c99b49827351ba4",
};
for (const file of [
  "vendor/win32-x64/ffmpeg.exe",
  "vendor/win32-x64/ffprobe.exe",
  "node_modules/uiohook-napi/prebuilds/win32-x64/node.napi.node",
  "node_modules/@koromix/koffi-win32-x64/win32_x64/koffi.node",
]) {
  const data = await readFile(file);
  if (data.readUInt16LE(0) !== 0x5a4d) throw new Error(`Invalid PE: ${file}`);
  const digest = createHash("sha256").update(data).digest("hex");
  if (expected[file] && expected[file] !== digest)
    throw new Error(`Unexpected media binary: ${file}`);
  const pe = data.readUInt32LE(0x3c);
  if (data.readUInt32LE(pe) !== 0x4550 || data.readUInt16LE(pe + 4) !== 0x8664)
    throw new Error(`Expected Windows x64: ${file}`);
  console.log(
    `${file}: x64, ${data.length} bytes, sha256 ${createHash("sha256").update(data).digest("hex")}`,
  );
}
