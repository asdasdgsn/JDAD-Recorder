import {
  mkdir,
  readFile,
  writeFile,
  rename,
  realpath,
  stat,
  open,
  unlink,
} from "node:fs/promises";
import type { FileHandle } from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { validateProject } from "../core";
import type { Project, ProjectHandle, RecentProject } from "../shared/types";

function within(root: string, file: string): boolean {
  const relative = path.relative(root, file);
  return (
    relative === "" ||
    (!relative.startsWith(".." + path.sep) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  );
}
export async function atomicJSON(file: string, value: unknown): Promise<void> {
  await mkdir(path.dirname(file), { recursive: true });
  const temp = file + "." + randomUUID() + ".tmp";
  try {
    await writeFile(temp, JSON.stringify(value, null, 2), { flag: "wx" });
    await rename(temp, file);
  } catch (error) {
    await unlink(temp).catch(() => {});
    throw error;
  }
}
export class RecordingWriter {
  private queue: Promise<void> = Promise.resolve();
  private failure: unknown;
  private closing?: Promise<void>;
  private closed = false;
  private constructor(private handle: FileHandle) {}
  static async create(file: string) {
    return new RecordingWriter(await open(file, "wx"));
  }
  append(chunk: Uint8Array): Promise<void> {
    if (this.closed || this.closing)
      return Promise.reject(new Error("录制文件正在关闭。"));
    if (!chunk.byteLength || chunk.byteLength > 32 * 1024 * 1024)
      return Promise.reject(new Error("录制数据块大小异常。"));
    const pending = this.queue.then(async () => {
      if (this.failure) throw this.failure;
      await this.handle.writeFile(chunk);
    });
    this.queue = pending.catch((error) => {
      this.failure = error;
    });
    return pending;
  }
  finish(): Promise<void> {
    if (!this.closing)
      this.closing = (async () => {
        await this.queue;
        this.closed = true;
        try {
          await this.handle.sync();
        } finally {
          await this.handle.close();
        }
        if (this.failure) throw this.failure;
      })();
    return this.closing;
  }
}
type SavedRecent = RecentProject & { root: string };
export class ProjectStore {
  active?: {
    root: string;
    sourcePath: string;
    mediaId: string;
    project: Project;
  };
  private writes: Promise<void> = Promise.resolve();
  constructor(
    private dataDirectory: string,
    private moviesDirectory: string,
  ) {}
  async createFolder(): Promise<string> {
    await mkdir(this.moviesDirectory, { recursive: true });
    const name =
      new Date().toISOString().replace(/[:.]/g, "-") +
      "-" +
      randomUUID().slice(0, 8) +
      ".jdadrec";
    const folder = path.join(this.moviesDirectory, name);
    await mkdir(path.join(folder, "media"), { recursive: true });
    await writeFile(path.join(folder, "recording.inprogress"), "");
    return folder;
  }
  async open(root: string): Promise<ProjectHandle> {
    await this.writes;
    const canonical = await realpath(root);
    const metadata = path.join(canonical, "project.json");
    if ((await stat(metadata)).size > 40 * 1024 * 1024)
      throw new Error("工程数据过大。");
    const project: unknown = JSON.parse(await readFile(metadata, "utf8"));
    validateProject(project);
    const sourcePath = await realpath(path.join(canonical, project.source));
    if (!within(canonical, sourcePath) || !(await stat(sourcePath)).isFile())
      throw new Error("素材必须位于工程目录内。");
    const mediaId = randomUUID();
    this.active = { root: canonical, sourcePath, mediaId, project };
    await this.remember(canonical, project);
    return { project, mediaUrl: `jdad-media://video/${mediaId}` };
  }
  async save(project: Project): Promise<void> {
    validateProject(project);
    const active = this.active;
    if (
      !active ||
      project.id !== active.project.id ||
      project.source !== active.project.source ||
      project.duration !== active.project.duration ||
      project.width !== active.project.width ||
      project.height !== active.project.height ||
      project.hasAudio !== active.project.hasAudio
    )
      throw new Error("工程素材信息已改变，请重新打开工程。");
    const snapshot = structuredClone(project);
    const pending = this.writes.then(async () => {
      await atomicJSON(path.join(active.root, "project.json"), snapshot);
      if (this.active === active) active.project = snapshot;
    });
    this.writes = pending.catch(() => {});
    return pending;
  }
  async complete(root: string, project: Project): Promise<ProjectHandle> {
    validateProject(project);
    await atomicJSON(path.join(root, "project.json"), project);
    await unlink(path.join(root, "recording.inprogress")).catch(() => {});
    return this.open(root);
  }
  async recent(): Promise<RecentProject[]> {
    return (await this.entries()).map(({ root, ...row }) => row);
  }
  async openRecent(id: string): Promise<ProjectHandle> {
    const entry = (await this.entries()).find((row) => row.id === id);
    if (!entry) throw new Error("找不到最近工程。");
    return this.open(entry.root);
  }
  async assertExportDestination(destination: string): Promise<void> {
    const active = this.active;
    if (!active) throw new Error("请先打开工程。");
    const parent = await realpath(path.dirname(destination));
    let target = path.join(parent, path.basename(destination));
    try {
      target = await realpath(destination);
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
    }
    if (within(active.root, target) || target === active.sourcePath)
      throw new Error("导出不能覆盖工程或原始素材，请选择其他文件夹。");
  }
  mediaPath(id: string): string | undefined {
    return this.active?.mediaId === id ? this.active.sourcePath : undefined;
  }
  async flush() {
    await this.writes;
  }
  private async entries(): Promise<SavedRecent[]> {
    try {
      const value: unknown = JSON.parse(
        await readFile(path.join(this.dataDirectory, "recent.json"), "utf8"),
      );
      if (!Array.isArray(value)) return [];
      return value
        .filter(
          (x) =>
            x &&
            typeof x.id === "string" &&
            typeof x.root === "string" &&
            typeof x.name === "string" &&
            typeof x.modified === "string",
        )
        .slice(0, 20);
    } catch {
      return [];
    }
  }
  private async remember(root: string, project: Project) {
    const entries = await this.entries();
    const id = entries.find((x) => x.root === root)?.id ?? randomUUID();
    await atomicJSON(
      path.join(this.dataDirectory, "recent.json"),
      [
        { id, root, name: project.name, modified: new Date().toISOString() },
        ...entries.filter((x) => x.root !== root),
      ].slice(0, 20),
    );
  }
}
