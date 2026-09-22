import path from "node:path";
import { randomUUID } from "node:crypto";
import { unlink } from "node:fs/promises";
import { planZooms } from "../core";
import type {
  CaptureOptions,
  CaptureSource,
  Project,
  ProjectHandle,
  Sample,
} from "../shared/types";
import { ProjectStore, RecordingWriter } from "./store";
import { finalizeRecording } from "./media";
import { trackPointer, windowBounds } from "./native";
export class CaptureSession {
  readonly token = randomUUID();
  private pointer?: ReturnType<typeof trackPointer>;
  private samples: Sample[] = [];
  private warnings: string[] = [];
  private finishing?: Promise<ProjectHandle>;
  private started = false;
  private constructor(
    readonly root: string,
    readonly options: CaptureOptions,
    readonly source: CaptureSource,
    private writer: RecordingWriter,
    private store: ProjectStore,
  ) {}
  static async create(
    options: CaptureOptions,
    source: CaptureSource,
    store: ProjectStore,
  ) {
    const root = await store.createFolder();
    return new CaptureSession(
      root,
      options,
      source,
      await RecordingWriter.create(path.join(root, "media/recording.webm")),
      store,
    );
  }
  start(epoch: number) {
    if (this.started) throw new Error("录制已经开始。");
    if (!Number.isFinite(epoch) || Math.abs(Date.now() - epoch) > 30000)
      throw new Error("录制时间无效。");
    this.started = true;
    this.pointer = trackPointer(
      () =>
        this.source.kind === "window"
          ? windowBounds(this.source.id)
          : this.source.bounds,
      this.options.region,
      epoch,
      (sample) => {
        if (this.samples.length < 2_000_000) this.samples.push(sample);
      },
    );
    this.warnings = this.pointer.warnings;
    return { warnings: this.warnings };
  }
  append(chunk: ArrayBuffer) {
    if (!(chunk instanceof ArrayBuffer)) throw new Error("无效录制数据。");
    return this.writer.append(new Uint8Array(chunk));
  }
  finish() {
    if (!this.finishing)
      this.finishing = this.finalize().catch((error) => {
        throw new Error(
          String(error) +
            "\n录制数据保留在：" +
            this.root +
            "。可以从“打开工程”尝试恢复。",
        );
      });
    return this.finishing;
  }
  private async finalize() {
    this.pointer?.stop();
    await this.writer.finish();
    const raw = path.join(this.root, "media/recording.webm");
    const meta = await finalizeRecording(
      raw,
      path.join(this.root, "media/original.webm"),
    );
    const samples = this.samples.filter((s) => s.time <= meta.duration);
    const project: Project = {
      version: 1,
      id: randomUUID(),
      name: "录制 " + new Date().toLocaleString("zh-CN"),
      source: "media/original.webm",
      ...meta,
      kept: [{ start: 0, end: meta.duration }],
      zooms: planZooms(samples, meta.duration),
      samples,
      autoZoom: true,
    };
    const handle = await this.store.complete(this.root, project);
    await unlink(raw).catch(() => {});
    return { ...handle, warnings: this.warnings };
  }
  async abort() {
    this.pointer?.stop();
    await this.writer.finish();
  }
}
