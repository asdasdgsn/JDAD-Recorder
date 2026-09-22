import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import {
  mkdtemp,
  open,
  realpath,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import {
  cameraAt,
  duration,
  selectRange,
  sourceTime,
  validateProject,
} from "../core/index";
import type { ExportSettings, Project } from "../shared/types";

export function mediaBinaries() {
  const resources = (process as NodeJS.Process & { resourcesPath?: string })
    .resourcesPath;
  const root =
    resources && existsSync(join(resources, "media"))
      ? join(resources, "media")
      : resolve(
          __dirname,
          "../../vendor",
          `${process.platform}-${process.arch}`,
        );
  const fallback = resolve(
    process.cwd(),
    "vendor",
    `${process.platform}-${process.arch}`,
  );
  const built = resolve(
    __dirname,
    "../vendor",
    `${process.platform}-${process.arch}`,
  );
  const base = existsSync(root) ? root : existsSync(built) ? built : fallback;
  const ext = process.platform === "win32" ? ".exe" : "";
  return {
    ffmpeg: process.env.FFMPEG_PATH || join(base, `ffmpeg${ext}`),
    ffprobe: process.env.FFPROBE_PATH || join(base, `ffprobe${ext}`),
  };
}
const aborted = () =>
  Object.assign(new Error("导出已取消"), { name: "AbortError" });
function run(
  binary: string,
  args: string[],
  signal?: AbortSignal,
  progress?: (line: string) => void,
  cwd?: string,
): Promise<string> {
  return new Promise((accept, reject) => {
    if (signal?.aborted) return reject(aborted());
    const child = spawn(binary, args, {
      windowsHide: true,
      cwd,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "",
      stderr = "",
      pending = "";
    let timer: NodeJS.Timeout | undefined;
    const cancel = () => {
      child.kill("SIGTERM");
      timer = setTimeout(() => child.kill("SIGKILL"), 2000);
      timer.unref();
    };
    signal?.addEventListener("abort", cancel, { once: true });
    child.stdout.on("data", (data: Buffer) => {
      if (progress) {
        pending += data.toString();
        const lines = pending.split("\n");
        pending = lines.pop() || "";
        lines.forEach(progress);
      } else {
        stdout += data.toString();
        if (stdout.length > 8 * 1024 * 1024) child.kill();
      }
    });
    child.stderr.on("data", (data: Buffer) => {
      stderr = (stderr + data.toString()).slice(-16000);
    });
    const cleanup = () => {
      if (timer) clearTimeout(timer);
      signal?.removeEventListener("abort", cancel);
    };
    child.on("error", (error) => {
      cleanup();
      reject(error);
    });
    child.on("close", (code) => {
      cleanup();
      if (signal?.aborted) reject(aborted());
      else if (code !== 0)
        reject(new Error(`媒体处理失败 (${code}): ${stderr}`));
      else accept(stdout);
    });
  });
}
export async function probeMedia(path: string) {
  const data = JSON.parse(
    await run(mediaBinaries().ffprobe, [
      "-v",
      "error",
      "-show_format",
      "-show_streams",
      "-of",
      "json",
      path,
    ]),
  );
  const video = data.streams.find(
    (s: { codec_type: string }) => s.codec_type === "video",
  );
  const seconds =
    [data.format?.duration, video?.duration]
      .map(Number)
      .find((value) => Number.isFinite(value) && value > 0) ?? NaN;
  if (
    !video ||
    !Number.isFinite(seconds) ||
    seconds <= 0 ||
    !Number.isInteger(video.width) ||
    !Number.isInteger(video.height)
  )
    throw new Error("无法读取有效视频时长或尺寸");
  const rotation = Number(
    video.side_data_list?.find(
      (entry: { rotation?: number }) => entry.rotation !== undefined,
    )?.rotation ??
      video.tags?.rotate ??
      0,
  );
  const quarterTurn = Math.abs(Math.round(rotation / 90)) % 2 === 1;
  return {
    duration: seconds,
    width: quarterTurn ? video.height : video.width,
    height: quarterTurn ? video.width : video.height,
    hasAudio: data.streams.some(
      (s: { codec_type: string }) => s.codec_type === "audio",
    ),
  };
}
export async function finalizeRecording(input: string, output: string) {
  const work = await mkdtemp(join(dirname(output), ".jdad-remux-"));
  try {
    const temporary = join(work, "seekable.webm");
    await run(mediaBinaries().ffmpeg, [
      "-hide_banner",
      "-loglevel",
      "error",
      "-n",
      "-i",
      input,
      "-map",
      "0:v:0",
      "-map",
      "0:a?",
      "-c",
      "copy",
      temporary,
    ]);
    const metadata = await probeMedia(temporary);
    if (existsSync(output)) throw new Error("录制目标已存在");
    await rename(temporary, output);
    return metadata;
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}
export async function exportMedia(
  project: Project,
  sourcePath: string,
  destination: string,
  settings: ExportSettings,
  signal: AbortSignal,
  onProgress: (progress: number) => void,
): Promise<void> {
  validateProject(project);
  if (
    !["mp4", "gif"].includes(settings.format) ||
    !Number.isFinite(settings.longEdge) ||
    settings.longEdge < 16 ||
    settings.longEdge > 7680 ||
    !Number.isFinite(settings.fps) ||
    settings.fps < 1 ||
    settings.fps > 60
  )
    throw new Error("无效导出设置");
  const source = await realpath(sourcePath);
  let target = resolve(destination);
  try {
    target = await realpath(destination);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
  }
  if (source === target) throw new Error("导出不能覆盖原素材");
  const kept = settings.selection
    ? selectRange(project.kept, settings.selection)
    : project.kept;
  const total = duration(kept);
  if (total <= 0) throw new Error("没有可导出片段");
  if (signal.aborted) throw aborted();
  const work = await mkdtemp(join(dirname(destination), ".jdad-export-"));
  const result = join(work, `result.${settings.format}`);
  try {
    onProgress(0);
    if (signal.aborted) throw aborted();
    const size = (n: number) => Math.max(2, Math.round(n / 2) * 2);
    const ratio = settings.longEdge / Math.max(project.width, project.height);
    const width = size(project.width * ratio),
      height = size(project.height * ratio);
    const command = await open(join(work, "camera.txt"), "w");
    try {
      let buffer = "",
        previous = "";
      for (let frame = 0; frame < Math.ceil(total * settings.fps); frame++) {
        if (signal.aborted) throw aborted();
        const time = frame / settings.fps;
        const camera = cameraAt(project, sourceTime(kept, time) ?? 0);
        const w = Math.min(project.width, size(project.width / camera.scale)),
          h = Math.min(project.height, size(project.height / camera.scale));
        const x = Math.max(
            0,
            Math.min(
              project.width - w,
              Math.round(camera.centerX * project.width - w / 2),
            ),
          ),
          y = Math.max(
            0,
            Math.min(
              project.height - h,
              Math.round(camera.centerY * project.height - h / 2),
            ),
          );
        const state = `crop w ${w}, crop h ${h}, crop x ${x}, crop y ${y}, scale w ${width}, scale h ${height}`;
        if (state !== previous) {
          buffer += `${time.toFixed(8)} ${state};\n`;
          previous = state;
        }
        if (frame % 1000 === 999) {
          await command.write(buffer);
          buffer = "";
        }
      }
      if (buffer) await command.write(buffer);
    } finally {
      await command.close();
    }
    const audio = project.hasAudio && settings.format === "mp4";
    const graph: string[] = [];
    // Normalize one segment at a time: no frame queues spanning reordered inputs.
    // Lossless intermediates live on disk and are deleted on success or cancellation.
    let normalized = 0;
    const concat: string[] = [];
    for (let i = 0; i < kept.length; i++) {
      const span = kept[i],
        length = span.end - span.start;
      const segment = `segment-${i}.mkv`;
      const prepare = [
        "-hide_banner",
        "-loglevel",
        "error",
        "-nostdin",
        "-ss",
        String(span.start),
        "-i",
        source,
        "-map",
        "0:v:0",
      ];
      if (audio)
        prepare.push(
          "-map",
          "0:a:0",
          "-af",
          `apad,atrim=duration=${length}`,
          "-c:a",
          "pcm_s16le",
        );
      else prepare.push("-an");
      prepare.push(
        "-t",
        String(length),
        "-c:v",
        "ffv1",
        "-level",
        "3",
        "-threads",
        "2",
        "-progress",
        "pipe:1",
        "-nostats",
        join(work, segment),
      );
      await run(mediaBinaries().ffmpeg, prepare, signal, (line) => {
        const m = /^out_time_us=(\d+)/.exec(line);
        if (m)
          onProgress(
            Math.min(0.35, (0.35 * (normalized + Number(m[1]) / 1e6)) / total),
          );
      });
      concat.push(`file '${segment}'`, `duration ${length}`);
      normalized += length;
    }
    await writeFile(join(work, "segments.txt"), concat.join("\n") + "\n");
    const filters = `[0:v]fps=${settings.fps},sendcmd=f=camera.txt,crop@camera=${project.width}:${project.height}:0:0,scale@output=${width}:${height}:flags=lanczos:eval=frame,setsar=1`;
    if (settings.format === "gif") {
      graph.push(
        `${filters},split[p1][p2]`,
        "[p1]palettegen=stats_mode=single[palette]",
        "[p2][palette]paletteuse=new=1:dither=sierra2_4a[video]",
      );
    } else graph.push(`${filters},format=yuv420p[video]`);
    await writeFile(join(work, "filter.txt"), graph.join(";\n"));
    const args = [
      "-hide_banner",
      "-loglevel",
      "error",
      "-nostdin",
      "-f",
      "concat",
      "-safe",
      "1",
      "-i",
      "segments.txt",
      "-filter_complex_threads",
      "1",
      "-filter_complex_script",
      "filter.txt",
      "-map",
      "[video]",
    ];
    if (audio) args.push("-map", "0:a:0", "-c:a", "aac", "-b:a", "160k");
    if (settings.format === "mp4")
      args.push(
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "20",
        "-movflags",
        "+faststart",
      );
    else args.push("-loop", "0");
    args.push("-t", String(total), "-progress", "pipe:1", "-nostats", result);
    await run(
      mediaBinaries().ffmpeg,
      args,
      signal,
      (line) => {
        const match = /^out_time_us=(\d+)/.exec(line);
        if (match)
          onProgress(
            Math.min(0.99, 0.35 + (0.64 * Number(match[1])) / 1e6 / total),
          );
      },
      work,
    );
    if (signal.aborted) throw aborted();
    await rename(result, destination);
    onProgress(1);
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}
