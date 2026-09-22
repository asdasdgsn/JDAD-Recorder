import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, readdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import {
  exportMedia,
  finalizeRecording,
  mediaBinaries,
  probeMedia,
} from "../src/main/media";
import type { Project } from "../src/shared/types";

test(
  "media: real reordered MP4, animated crop, audio, GIF and cancellation",
  { timeout: 120000 },
  async () => {
    const dir = await mkdtemp(join(tmpdir(), "jdad-test-"));
    const { ffmpeg } = mediaBinaries();
    try {
      const src = join(dir, "source.mp4");
      execFileSync(ffmpeg, [
        "-hide_banner",
        "-loglevel",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=red:s=160x90:r=12:d=2",
        "-f",
        "lavfi",
        "-i",
        "color=blue:s=160x90:r=12:d=2",
        "-f",
        "lavfi",
        "-i",
        "sine=frequency=440:duration=4",
        "-filter_complex",
        "[0:v][1:v]concat=n=2:v=1:a=0[v]",
        "-map",
        "[v]",
        "-map",
        "2:a",
        "-af",
        "volume='if(lt(t,2),1,0)':eval=frame",
        "-c:v",
        "libx264",
        "-c:a",
        "aac",
        src,
      ]);
      const raw = join(dir, "stream.webm");
      await writeFile(
        raw,
        execFileSync(ffmpeg, [
          "-v",
          "error",
          "-i",
          src,
          "-t",
          "1",
          "-c:v",
          "libvpx",
          "-c:a",
          "libopus",
          "-f",
          "webm",
          "pipe:1",
        ]),
      );
      const finalized = await finalizeRecording(
        raw,
        join(dir, "seekable.webm"),
      );
      assert.ok(finalized.duration >= 0.9);
      const project: Project = {
        version: 1,
        id: "fixture",
        name: "fixture",
        source: "media/source.mp4",
        duration: 4,
        width: 160,
        height: 90,
        hasAudio: true,
        kept: [
          { start: 2, end: 4 },
          { start: 0, end: 2 },
        ],
        zooms: [],
        samples: [],
        autoZoom: false,
      };
      const rotated = join(dir, "rotated.mp4");
      execFileSync(ffmpeg, [
        "-v",
        "error",
        "-i",
        src,
        "-c",
        "copy",
        "-metadata:s:v:0",
        "rotate=90",
        rotated,
      ]);
      const portrait = await probeMedia(rotated);
      assert.equal(portrait.width, 90);
      assert.equal(portrait.height, 160);
      const portraitOutput = join(dir, "portrait.mp4");
      await exportMedia(
        { ...project, width: 90, height: 160 },
        rotated,
        portraitOutput,
        {
          format: "mp4",
          longEdge: 160,
          fps: 12,
          selection: { start: 0, end: 1 },
        },
        new AbortController().signal,
        () => {},
      );
      assert.equal((await probeMedia(portraitOutput)).height, 160);
      const out = join(dir, "result.mp4");
      await writeFile(out, "previous output");
      await exportMedia(
        project,
        src,
        out,
        { format: "mp4", longEdge: 160, fps: 12 },
        new AbortController().signal,
        () => {},
      );
      const info = await probeMedia(out);
      assert.ok(Math.abs(info.duration - 4) < 0.15);
      assert.equal(info.hasAudio, true);
      assert.equal(info.width, 160);
      const pixel = (t: number) =>
        execFileSync(ffmpeg, [
          "-v",
          "error",
          "-ss",
          String(t),
          "-i",
          out,
          "-frames:v",
          "1",
          "-vf",
          "scale=1:1",
          "-f",
          "rawvideo",
          "-pix_fmt",
          "rgb24",
          "pipe:1",
        ]);
      assert.ok(pixel(0.5)[2] > 200);
      assert.ok(pixel(2.5)[0] > 200);
      const energy = (time: number) => {
        const data = execFileSync(ffmpeg, [
          "-v",
          "error",
          "-ss",
          String(time),
          "-t",
          "0.3",
          "-i",
          out,
          "-vn",
          "-f",
          "f32le",
          "-ac",
          "1",
          "pipe:1",
        ]);
        let sum = 0;
        for (let i = 0; i < data.length; i += 4)
          sum += data.readFloatLE(i) ** 2;
        return sum / (data.length / 4);
      };
      assert.ok(
        energy(0.5) < energy(2.5) * 0.01,
        "audio follows reordered clips",
      );
      const half = join(dir, "halves.mp4");
      execFileSync(ffmpeg, [
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "color=red:s=160x90:r=12:d=2",
        "-vf",
        "drawbox=x=80:y=0:w=80:h=90:color=blue:t=fill",
        "-c:v",
        "libx264",
        half,
      ]);
      const zoomed = join(dir, "zoom.mp4");
      await exportMedia(
        {
          ...project,
          duration: 2,
          hasAudio: false,
          kept: [{ start: 0, end: 2 }],
          zooms: [
            {
              id: "zoom",
              start: 0,
              end: 2,
              centerX: 0.75,
              centerY: 0.5,
              scale: 2,
              manual: true,
            },
          ],
        },
        half,
        zoomed,
        { format: "mp4", longEdge: 160, fps: 12 },
        new AbortController().signal,
        () => {},
      );
      const cropPixel = execFileSync(ffmpeg, [
        "-v",
        "error",
        "-ss",
        "1",
        "-i",
        zoomed,
        "-frames:v",
        "1",
        "-vf",
        "scale=1:1",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "pipe:1",
      ]);
      assert.ok(
        cropPixel[2] > 200 && cropPixel[0] < 40,
        "shared camera zoom crops to blue half " + cropPixel.toString("hex"),
      );
      const gif = join(dir, "result.gif");
      await exportMedia(
        project,
        src,
        gif,
        {
          format: "gif",
          longEdge: 160,
          fps: 6,
          selection: { start: 0, end: 1 },
        },
        new AbortController().signal,
        () => {},
      );
      assert.equal((await readFile(gif)).subarray(0, 3).toString(), "GIF");
      const frames = execFileSync(ffmpeg, [
        "-v",
        "error",
        "-i",
        gif,
        "-vf",
        "scale=1:1",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "pipe:1",
      ]);
      assert.ok(frames.length >= 18, "GIF contains multiple decoded frames");
      assert.ok((await probeMedia(gif)).duration >= 0.8);
      await assert.rejects(
        exportMedia(
          project,
          src,
          src,
          { format: "mp4", longEdge: 160, fps: 12 },
          new AbortController().signal,
          () => {},
        ),
        /原素材/,
      );
      const destination = join(dir, "existing.mp4");
      await writeFile(destination, "keep me");
      const controller = new AbortController();
      await assert.rejects(
        exportMedia(
          project,
          src,
          destination,
          { format: "mp4", longEdge: 160, fps: 12 },
          controller.signal,
          (p) => {
            if (p > 0.35) controller.abort();
          },
        ),
        { name: "AbortError" },
      );
      assert.equal(await readFile(destination, "utf8"), "keep me");
      assert.ok(
        (await readdir(dir)).every((name) => !name.startsWith(".jdad-")),
        "all temporary export directories removed",
      );
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  },
);

test("media: packaged Windows tools are native x64 PE executables", async () => {
  for (const name of ["ffmpeg.exe", "ffprobe.exe"]) {
    const binary = await readFile(join(__dirname, "../vendor/win32-x64", name));
    assert.equal(binary.subarray(0, 2).toString(), "MZ");
    const pe = binary.readUInt32LE(0x3c);
    assert.equal(binary.subarray(pe, pe + 4).toString(), "PE\0\0");
    assert.equal(binary.readUInt16LE(pe + 4), 0x8664);
  }
});
