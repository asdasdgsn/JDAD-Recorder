import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, mkdir, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { ProjectStore, RecordingWriter } from "../src/main/store";
import type { Project } from "../src/shared/types";
const project: Project = {
  version: 1,
  id: "test",
  name: "测试",
  source: "media/original.webm",
  duration: 4,
  width: 320,
  height: 180,
  hasAudio: false,
  kept: [{ start: 0, end: 4 }],
  zooms: [],
  samples: [],
  autoZoom: true,
};
test("store serializes chunks and waits for the last write before close", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "jdad-writes-"));
  const file = path.join(root, "source.webm");
  const writer = await RecordingWriter.create(file);
  const tasks = [
    writer.append(Buffer.from("one")),
    writer.append(Buffer.from("two")),
    writer.append(Buffer.from("three")),
  ];
  await Promise.all([writer.finish(), ...tasks]);
  await writer.finish();
  assert.equal(await readFile(file, "utf8"), "onetwothree");
  await assert.rejects(() => writer.append(Buffer.from("late")));
});
test("project save roundtrip binds source and blocks traversal", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "jdad-store-"));
  const store = new ProjectStore(
    path.join(root, "data"),
    path.join(root, "videos"),
  );
  const folder = await store.createFolder();
  await mkdir(path.join(folder, "media"), { recursive: true });
  await writeFile(path.join(folder, project.source), "fixture");
  await writeFile(path.join(folder, "project.json"), JSON.stringify(project));
  const loaded = await store.open(folder);
  await store.save({ ...loaded.project, name: "改名" });
  assert.equal((await store.open(folder)).project.name, "改名");
  await assert.rejects(() =>
    store.save({ ...project, source: "../outside.webm" }),
  );
  await assert.rejects(() =>
    store.assertExportDestination(path.join(folder, project.source)),
  );
});
test("project refuses media symlink escaping its folder", async () => {
  const root = await mkdtemp(path.join(tmpdir(), "jdad-link-"));
  const store = new ProjectStore(
    path.join(root, "data"),
    path.join(root, "videos"),
  );
  const folder = await store.createFolder();
  await mkdir(path.join(folder, "media"), { recursive: true });
  await writeFile(path.join(root, "outside.webm"), "private");
  await symlink(
    path.join(root, "outside.webm"),
    path.join(folder, project.source),
  );
  await writeFile(path.join(folder, "project.json"), JSON.stringify(project));
  await assert.rejects(() => store.open(folder), /工程|素材/);
});
