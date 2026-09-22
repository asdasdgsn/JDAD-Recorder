import { mkdtemp, mkdir, rm, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
const target = "node_modules/@koromix/koffi-win32-x64";
try {
  await access(join(target, "win32_x64/koffi.node"));
} catch {
  const temp = await mkdtemp(join(tmpdir(), "jdad-native-"));
  try {
    execFileSync(
      process.platform === "win32" ? "npm.cmd" : "npm",
      [
        "pack",
        "@koromix/koffi-win32-x64@3.3.1",
        "--registry=https://registry.npmjs.org",
        "--pack-destination",
        temp,
      ],
      { stdio: "inherit" },
    );
    await mkdir(target, { recursive: true });
    execFileSync(
      "tar",
      [
        "-xzf",
        join(temp, "koromix-koffi-win32-x64-3.3.1.tgz"),
        "-C",
        target,
        "--strip-components=1",
      ],
      { stdio: "inherit" },
    );
  } finally {
    await rm(temp, { recursive: true, force: true });
  }
}
