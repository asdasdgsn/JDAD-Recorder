import type {
  Project,
  ProjectHandle,
  Rect,
  CaptureSource,
  Zoom,
} from "../shared/types";
import {
  duration,
  boundaries,
  sourceTime,
  split,
  moveClip,
  selectRange,
  deleteRange,
  cameraAt,
  resizeZoom,
  snap,
} from "../core/index";
const api = window.jdad,
  app = document.querySelector<HTMLDivElement>("#app")!;
let handle: ProjectHandle | null = null,
  undo: Project[] = [],
  redo: Project[] = [],
  view = "record",
  busy = false,
  exporting = false,
  playing = false,
  playhead = 0,
  selectedClip = 0,
  range = { start: 0, end: 0 },
  timelineScale = 45;
let sources: CaptureSource[] = [],
  selectedSource = "",
  region: Rect | undefined,
  microphone = false,
  saveChain = Promise.resolve(),
  saveTimer: ReturnType<typeof setTimeout> | undefined;
const video = document.createElement("video");
video.preload = "auto";
video.playsInline = true;
let toastTimer: ReturnType<typeof setTimeout>;
function toast(message: string) {
  const el = document.querySelector<HTMLDivElement>("#toast")!;
  el.textContent = message;
  el.style.display = "block";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.style.display = "none"), 7000);
}
function error(e: unknown) {
  toast(e instanceof Error ? e.message : String(e));
}
const html = (s: string) =>
  s.replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ]!,
  );
const time = (n: number) =>
  `${Math.floor(n / 60)
    .toString()
    .padStart(2, "0")}:${(n % 60).toFixed(1).padStart(4, "0")}`;
const on = (id: string, fn: () => unknown) =>
  document.getElementById(id)?.addEventListener("click", () => {
    Promise.resolve().then(fn).catch(error);
  });
function shell(body: string) {
  app.innerHTML = `<aside><div class="brand">JDAD<span>RECORDER</span></div><button id="recordNav" class="${view === "record" ? "active" : ""}">◉　开始录制</button><button id="libraryNav" class="${view === "library" ? "active" : ""}">▦　我的作品</button>${handle ? '<button id="editorNav">▤　继续剪辑</button>' : ""}<button id="more">发现更多应用与功能 ↗</button></aside><main>${body}</main>`;
  on("more", () => api.openMore());
  on("recordNav", () => {
    if (!busy && !exporting) {
      pause();
      view = "record";
      renderRecord();
    }
  });
  on("libraryNav", () => {
    if (!busy && !exporting) {
      pause();
      view = "library";
      void renderLibrary();
    }
  });
  on("editorNav", () => {
    if (!busy && !exporting) {
      view = "editor";
      renderEditor();
    }
  });
}
let switchingProject = false,
  snapEnabled = true;
async function switchProject(open: () => Promise<ProjectHandle | null>) {
  if (switchingProject || busy || exporting) return;
  switchingProject = true;
  try {
    await flushSave();
    await loadProject(await open());
  } finally {
    switchingProject = false;
  }
}
async function loadProject(next: ProjectHandle | null) {
  if (!next) return;
  pause();
  handle = next;
  undo = [];
  redo = [];
  playhead = 0;
  range = { start: 0, end: duration(next.project.kept) };
  video.src = next.mediaUrl;
  video.load();
  view = "editor";
  renderEditor();
  if (next.warnings?.length) toast(next.warnings.join("；"));
}
function save() {
  if (!handle) return;
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void flushSave().catch(error), 450);
}
async function flushSave() {
  clearTimeout(saveTimer);
  if (!handle) return;
  const project = structuredClone(handle.project);
  saveChain = saveChain.catch(() => {}).then(() => api.saveProject(project));
  try {
    await saveChain;
    const el = document.querySelector("#saveStatus");
    if (el) el.textContent = "已自动保存";
  } catch (e) {
    error(e);
    const el = document.querySelector("#saveStatus");
    if (el) el.textContent = "保存失败，请重试";
    throw e;
  }
}
function change(project: Project) {
  if (!handle || exporting) return;
  undo.push(structuredClone(handle.project));
  if (undo.length > 100) undo.shift();
  redo = [];
  handle.project = project;
  playhead = Math.min(playhead, duration(project.kept));
  range.end = Math.min(range.end, duration(project.kept));
  range.start = Math.min(range.start, range.end);
  pause();
  save();
  renderEditor();
}
function history(forward: boolean) {
  if (!handle || exporting) return;
  const stack = forward ? redo : undo,
    other = forward ? undo : redo;
  if (!stack.length) return;
  other.push(handle.project);
  handle.project = stack.pop()!;
  playhead = Math.min(playhead, duration(handle.project.kept));
  range = { start: 0, end: duration(handle.project.kept) };
  pause();
  save();
  renderEditor();
}
async function renderLibrary() {
  shell(
    '<h1>我的作品</h1><p>从录制开始，也可以继续编辑已有视频。</p><div class="row"><button id="new" class="primary">新建录制</button><button id="import">导入视频</button><button id="open">打开工程</button></div><div class="panel" id="recent">正在加载…</div>',
  );
  on("new", () => {
    view = "record";
    renderRecord();
  });
  on("import", () => switchProject(() => api.importVideo()));
  on("open", () => switchProject(() => api.openProject()));
  const recent = await api.recent();
  const el = document.querySelector("#recent");
  if (!el) return;
  el.innerHTML = recent.length
    ? recent
        .map(
          (p, i) =>
            `<div class="library-item"><div>${html(p.name)}<p>${html(new Date(p.modified).toLocaleString())}</p></div><button data-recent="${i}">继续编辑 →</button></div>`,
        )
        .join("")
    : '<div class="empty">还没有作品，开始你的第一次录制吧。</div>';
  el.querySelectorAll<HTMLButtonElement>("[data-recent]").forEach(
    (b) =>
      (b.onclick = () =>
        void switchProject(() =>
          api.openRecent(recent[Number(b.dataset.recent)].id),
        ).catch(error)),
  );
}
function renderRecord() {
  shell(
    `<h1>清晰记录，每一个步骤。</h1><p>录制屏幕，轻松剪辑，让重点自然呈现。</p><div class="panel"><div class="row between"><h2>选择录制来源</h2><button id="refresh" ${busy ? "disabled" : ""}>刷新来源</button></div><div id="sources" class="sources"></div><div class="row"><button id="region" ${busy ? "disabled" : ""}>${region ? "已选择区域 · 重新框选" : "指定屏幕区域"}</button>${region ? '<button id="clearRegion">录制完整屏幕</button>' : ""}<label><input id="mic" type="checkbox" ${microphone ? "checked" : ""} ${busy ? "disabled" : ""}> 麦克风</label></div><p id="regionInfo">${region ? "将只录制所选区域" : "默认不录制声音。选择应用窗口时，请保持窗口可见。"}</p><div class="row"><button class="primary" id="start" ${busy ? "disabled" : ""}>开始录制</button><button id="stop" ${recorder?.state === "recording" ? "" : "disabled"}>停止并剪辑</button><span id="recordStatus" class="status">${busy ? "准备中…" : "准备就绪"}</span></div></div><footer>原始视频始终保留，剪辑会自动保存。</footer>`,
  );
  drawSources();
  on("refresh", refreshSources);
  on("region", async () => {
    const s = sources.find((s) => s.id === selectedSource);
    if (!s || s.kind !== "screen") {
      toast("请先选择一个屏幕，再框选录制区域。");
      return;
    }
    const next = await api.chooseRegion(selectedSource);
    if (next) {
      region = next;
      renderRecord();
    }
  });
  on("clearRegion", () => {
    region = undefined;
    renderRecord();
  });
  document.querySelector<HTMLInputElement>("#mic")!.onchange = (e) =>
    (microphone = (e.target as HTMLInputElement).checked);
  on("start", startCapture);
  on("stop", stopCapture);
}
function drawSources() {
  const el = document.querySelector("#sources");
  if (!el) return;
  el.innerHTML =
    sources
      .map(
        (s, i) =>
          `<button class="source ${s.id === selectedSource ? "selected" : ""}" data-source="${i}" ${busy ? "disabled" : ""}><img src="${html(s.thumbnail)}" alt="">${html(s.title)}<div class="muted">${s.kind === "screen" ? "显示器" : "应用窗口"}</div></button>`,
      )
      .join("") || "<p>点击“刷新来源”查看可录制的屏幕和窗口。</p>";
  el.querySelectorAll<HTMLButtonElement>("[data-source]").forEach(
    (b) =>
      (b.onclick = () => {
        selectedSource = sources[Number(b.dataset.source)].id;
        region = undefined;
        drawSources();
      }),
  );
}
async function refreshSources() {
  sources = await api.sources();
  if (!sources.some((s) => s.id === selectedSource)) {
    selectedSource = sources[0]?.id || "";
    region = undefined;
  }
  drawSources();
}
let recorder: MediaRecorder | null = null,
  token = "",
  captureStreams: MediaStream[] = [],
  chunkChain = Promise.resolve(),
  pendingBytes = 0,
  captureFailure: unknown = null,
  stopFlight: Promise<void> | null = null,
  cropFrame = 0,
  recordClock: ReturnType<typeof setInterval> | undefined,
  captureVideo: HTMLVideoElement | null = null;
let recorderStopped: Promise<void> = Promise.resolve(),
  resolveRecorderStopped: (() => void) | null = null,
  rejectCaptureStart: ((reason: unknown) => void) | null = null;
async function startCapture() {
  if (busy) return;
  if (!selectedSource) {
    toast("请先选择录制来源。");
    return;
  }
  busy = true;
  renderRecord();
  captureFailure = null;
  pendingBytes = 0;
  chunkChain = Promise.resolve();
  try {
    await flushSave();
    token = (await api.prepareCapture({ sourceId: selectedSource, region }))
      .token;
    const screen = await navigator.mediaDevices.getDisplayMedia({
      video: { frameRate: 30 },
      audio: false,
    });
    captureStreams = [screen];
    let output = screen;
    if (region) {
      const v = document.createElement("video");
      captureVideo = v;
      v.srcObject = screen;
      v.muted = true;
      await v.play();
      const c = document.createElement("canvas");
      c.width = Math.max(2, Math.round(v.videoWidth * region.width));
      c.height = Math.max(2, Math.round(v.videoHeight * region.height));
      const ctx = c.getContext("2d")!,
        r = { ...region };
      const draw = () => {
        ctx.drawImage(
          v,
          v.videoWidth * r.x,
          v.videoHeight * r.y,
          v.videoWidth * r.width,
          v.videoHeight * r.height,
          0,
          0,
          c.width,
          c.height,
        );
        cropFrame = requestAnimationFrame(draw);
      };
      draw();
      output = c.captureStream(30);
      captureStreams.push(output);
    }
    if (microphone) {
      try {
        const mic = await navigator.mediaDevices.getUserMedia({
          audio: true,
          video: false,
        });
        captureStreams.push(mic);
        mic.getAudioTracks().forEach((t) => output.addTrack(t));
      } catch {
        throw new Error(
          "无法使用麦克风。请检查 Windows 权限，或关闭麦克风后重新开始。",
        );
      }
    }
    for (let count = 3; count > 0; count--) {
      const el = document.querySelector("#recordStatus");
      if (el) el.textContent = `${count} 秒后开始…`;
      await new Promise((r) => setTimeout(r, 1000));
    }
    if (screen.getVideoTracks().some((t) => t.readyState === "ended"))
      throw new Error("录制来源已关闭，请重新选择。");
    const mime = [
      "video/webm;codecs=vp9,opus",
      "video/webm;codecs=vp8,opus",
      "video/webm",
    ].find((m) => MediaRecorder.isTypeSupported(m));
    if (!mime) throw new Error("当前设备无法使用视频编码器。");
    recorder = new MediaRecorder(output, {
      mimeType: mime,
      videoBitsPerSecond: 8_000_000,
    });
    const activeRecorder = recorder;
    recorderStopped = new Promise<void>(
      (resolve) => (resolveRecorderStopped = resolve),
    );
    recorder.onstop = () => {
      resolveRecorderStopped?.();
      resolveRecorderStopped = null;
      rejectCaptureStart?.(captureFailure ?? new Error("录制已停止。"));
      void stopCapture();
    };
    recorder.ondataavailable = (e) => {
      if (!e.data.size) return;
      pendingBytes += e.data.size;
      if (pendingBytes > 64 * 1024 * 1024) {
        captureFailure = new Error(
          "保存速度不足，录制已停止以避免占用过多内存。",
        );
        void stopCapture();
        return;
      }
      chunkChain = chunkChain
        .then(async () => {
          try {
            if (!captureFailure)
              await api.appendCapture(token, await e.data.arrayBuffer());
          } finally {
            pendingBytes -= e.data.size;
          }
        })
        .catch((e) => {
          captureFailure = e;
          void stopCapture();
        });
    };
    recorder.onerror = () => {
      captureFailure = new Error("录制中断，请重试。");
      rejectCaptureStart?.(captureFailure);
      void stopCapture();
    };
    screen
      .getVideoTracks()
      .forEach((t) => (t.onended = () => void stopCapture()));
    await new Promise<void>((resolve, reject) => {
      rejectCaptureStart = reject;
      recorder!.onstart = () => {
        api.captureStarted(token, Date.now()).then((result) => {
          if (result.warnings.length) toast(result.warnings.join("；"));
          resolve();
        }, reject);
      };
      try {
        recorder!.start(1000);
      } catch (e) {
        resolveRecorderStopped?.();
        resolveRecorderStopped = null;
        reject(e);
      }
    });
    rejectCaptureStart = null;
    if (recorder !== activeRecorder || stopFlight) return;
    const began = Date.now();
    renderRecord();
    recordClock = setInterval(() => {
      const el = document.querySelector("#recordStatus");
      if (el)
        el.innerHTML = `<span class="recording-dot"></span>正在录制 ${time((Date.now() - began) / 1000)} · 托盘可停止`;
    }, 500);
  } catch (e) {
    rejectCaptureStart = null;
    if (recorder) {
      captureFailure = captureFailure ?? e;
      await stopCapture();
    } else {
      cleanupCapture();
      if (token) await api.abortCapture(token).catch(() => {});
      token = "";
      busy = false;
      renderRecord();
      error(e);
    }
  }
}
function cleanupCapture() {
  if (recorder?.state === "recording") {
    recorder.ondataavailable = null;
    recorder.onstop = null;
    recorder.stop();
  }
  clearInterval(recordClock);
  cancelAnimationFrame(cropFrame);
  captureStreams.forEach((s) =>
    s.getTracks().forEach((t) => {
      t.onended = null;
      t.stop();
    }),
  );
  captureStreams = [];
  if (captureVideo) {
    captureVideo.pause();
    captureVideo.srcObject = null;
    captureVideo = null;
  }
  recorder = null;
}
function stopCapture(): Promise<void> {
  if (stopFlight) return stopFlight;
  if (!recorder) return Promise.resolve();
  const r = recorder,
    stopped = recorderStopped;
  stopFlight = (async () => {
    try {
      if (r.state === "recording" || r.state === "paused") r.stop();
      await stopped;
      await chunkChain;
      cleanupCapture();
      if (captureFailure) throw captureFailure;
      const result = await api.finishCapture(token);
      token = "";
      busy = false;
      await loadProject(result);
    } catch (e) {
      cleanupCapture();
      if (token) await api.abortCapture(token).catch(() => {});
      token = "";
      busy = false;
      renderRecord();
      error(e);
    } finally {
      stopFlight = null;
    }
  })();
  return stopFlight;
}
api.onStopRequest(() => void stopCapture());
let closing = false;
api.onCloseRequest(() => {
  if (closing) return;
  if (switchingProject || busy || exporting) {
    toast("请等待当前操作完成后再关闭。");
    return;
  }
  closing = true;
  (document.activeElement as HTMLElement | null)?.blur();
  pause();
  app.inert = true;
  void flushSave()
    .then(() => api.closeReady())
    .catch((e) => {
      closing = false;
      app.inert = false;
      error(e);
    });
});
function pause() {
  playing = false;
  video.pause();
}
function seek(t: number) {
  if (!handle) return;
  playhead = Math.max(0, Math.min(duration(handle.project.kept), t));
  const source = sourceTime(handle.project.kept, playhead);
  if (source !== null) video.currentTime = source;
  updateTransport();
}
function updateTransport() {
  const p = document.querySelector<HTMLInputElement>("#playhead");
  if (p) p.value = String(playhead);
  const t = document.querySelector("#time");
  if (t && handle)
    t.textContent = `${time(playhead)} / ${time(duration(handle.project.kept))}`;
  const b = document.querySelector("#play");
  if (b) b.textContent = playing ? "暂停" : "播放";
}
function renderEditor() {
  if (!handle) return;
  const p = handle.project,
    total = duration(p.kept);
  shell(
    `<div class="row between"><input class="title-input" id="name" aria-label="作品名称" value="${html(p.name)}"><div class="row"><span id="saveStatus" class="status">自动保存</span><button id="save">保存</button><button id="export" class="primary">导出作品 ↗</button></div></div><div class="panel"><canvas id="preview" class="preview" width="${p.width}" height="${p.height}"></canvas><div class="row transport"><button id="play">播放</button><input id="playhead" aria-label="播放位置" type="range" min="0" max="${total}" step="0.01" value="${playhead}" style="flex:1"><span id="time">${time(playhead)} / ${time(total)}</span></div><div class="row toolbar"><button id="undo" ${undo.length ? "" : "disabled"}>撤销</button><button id="redo" ${redo.length ? "" : "disabled"}>重做</button><button id="split">分割 Ctrl+B</button><button id="focus">＋ 聚焦</button><label><input id="autoZoom" type="checkbox" ${p.autoZoom ? "checked" : ""}> 自动聚焦</label><span style="flex:1"></span><label>时间轴 <input id="scale" type="range" min="10" max="180" value="${timelineScale}"></label></div><div id="timeline"><div id="selectionTrack"><div id="selectionShade"></div><button id="selectionStart" class="selection-handle" aria-label="拖动选区起点"></button><button id="selectionEnd" class="selection-handle" aria-label="拖动选区终点"></button></div><div id="clips"></div><div id="zooms"></div></div><div class="row toolbar"><label><input id="snapToggle" type="checkbox" ${snapEnabled ? "checked" : ""}> 吸附</label><span>选区</span><input id="rangeStart" class="timeinput" aria-label="选区开始秒数" type="number" min="0" max="${total}" step="0.1" value="${range.start.toFixed(2)}"><span>至</span><input id="rangeEnd" class="timeinput" aria-label="选区结束秒数" type="number" min="0" max="${total}" step="0.1" value="${range.end.toFixed(2)}"><span>秒</span><button id="keep">仅保留选区</button><button id="delete" class="danger">删除选区</button><button id="all">选择全部</button></div><p class="muted">拖动片段可调整顺序；点击聚焦条编辑位置，拖动两端调整时长。</p></div>`,
  );
  document.querySelector<HTMLInputElement>("#name")!.onchange = (e) =>
    change({
      ...p,
      name: (e.target as HTMLInputElement).value.trim() || "未命名作品",
    });
  on("save", flushSave);
  on("undo", () => history(false));
  on("redo", () => history(true));
  on("split", () => change({ ...p, kept: split(p.kept, playhead) }));
  on("play", async () => {
    if (playing) pause();
    else {
      if (playhead >= total) seek(0);
      playing = true;
      await video.play();
    }
    updateTransport();
  });
  document.querySelector<HTMLInputElement>("#playhead")!.oninput = (e) => {
    pause();
    seek(Number((e.target as HTMLInputElement).value));
  };
  on("focus", () => focusDialog());
  document.querySelector<HTMLInputElement>("#autoZoom")!.onchange = (e) =>
    change({ ...p, autoZoom: (e.target as HTMLInputElement).checked });
  document.querySelector<HTMLInputElement>("#scale")!.oninput = (e) => {
    timelineScale = Number((e.target as HTMLInputElement).value);
    drawTimeline();
  };
  document.querySelector<HTMLInputElement>("#snapToggle")!.onchange = (e) =>
    (snapEnabled = (e.target as HTMLInputElement).checked);
  for (const id of ["rangeStart", "rangeEnd"])
    document.querySelector<HTMLInputElement>("#" + id)!.onchange = () => {
      const a = Number(
          (document.querySelector("#rangeStart") as HTMLInputElement).value,
        ),
        b = Number(
          (document.querySelector("#rangeEnd") as HTMLInputElement).value,
        );
      if (!Number.isFinite(a) || !Number.isFinite(b)) return;
      range = {
        start: Math.max(0, Math.min(a, b, total)),
        end: Math.min(total, Math.max(a, b, 0)),
      };
      updateSelection();
    };
  on("keep", () => {
    if (range.end <= range.start) return toast("请选择一段有效范围。");
    change({ ...p, kept: selectRange(p.kept, range) });
  });
  on("delete", () => {
    if (range.end <= range.start) return;
    const kept = deleteRange(p.kept, range);
    if (!kept.length) return toast("至少保留一个视频片段。");
    change({ ...p, kept });
  });
  on("all", () => {
    range = { start: 0, end: total };
    renderEditor();
  });
  on("export", exportDialog);
  drawTimeline();
  seek(playhead);
}

function timelineSnap(value: number, factor: number) {
  return snapEnabled && handle
    ? snap(value, [...boundaries(handle.project.kept), playhead], 8 / factor)
    : value;
}
function updateSelection() {
  if (!handle) return;
  const track = document.querySelector<HTMLDivElement>("#selectionTrack");
  if (!track) return;
  const total = duration(handle.project.kept),
    factor = parseFloat(track.style.width) / total;
  const shade = document.querySelector<HTMLDivElement>("#selectionShade")!;
  shade.style.left = range.start * factor + "px";
  shade.style.width = (range.end - range.start) * factor + "px";
  document.querySelector<HTMLElement>("#selectionStart")!.style.left =
    range.start * factor + "px";
  document.querySelector<HTMLElement>("#selectionEnd")!.style.left =
    range.end * factor + "px";
  (document.querySelector("#rangeStart") as HTMLInputElement).value =
    range.start.toFixed(2);
  (document.querySelector("#rangeEnd") as HTMLInputElement).value =
    range.end.toFixed(2);
}
function configureSelection(width: number, factor: number) {
  const track = document.querySelector<HTMLDivElement>("#selectionTrack");
  if (!track || !handle) return;
  track.style.width = width + "px";
  const total = duration(handle.project.kept);
  for (const side of ["start", "end"] as const) {
    const grip = document.querySelector<HTMLButtonElement>(
      side === "start" ? "#selectionStart" : "#selectionEnd",
    )!;
    grip.onpointerdown = (e) => {
      e.preventDefault();
      pause();
      grip.setPointerCapture(e.pointerId);
      const move = (event: PointerEvent) => {
        const value = Math.max(
          0,
          Math.min(
            total,
            timelineSnap(
              (event.clientX - track.getBoundingClientRect().left) / factor,
              factor,
            ),
          ),
        );
        range =
          side === "start"
            ? { start: Math.min(value, range.end), end: range.end }
            : { start: range.start, end: Math.max(value, range.start) };
        updateSelection();
      };
      grip.onpointermove = move;
      grip.onpointerup = grip.onpointercancel = () => {
        grip.onpointermove = null;
        grip.onpointerup = null;
        grip.onpointercancel = null;
      };
    };
    grip.onkeydown = (e) => {
      if (e.key !== "ArrowLeft" && e.key !== "ArrowRight") return;
      e.preventDefault();
      const delta =
          (e.key === "ArrowLeft" ? -1 : 1) * (e.shiftKey ? 1 : 1 / 30),
        value = Math.max(0, Math.min(total, range[side] + delta));
      range =
        side === "start"
          ? { start: Math.min(value, range.end), end: range.end }
          : { start: range.start, end: Math.max(value, range.start) };
      updateSelection();
    };
  }
  updateSelection();
}
function drawTimeline() {
  if (!handle) return;
  const p = handle.project,
    clipEl = document.querySelector<HTMLDivElement>("#clips"),
    zoomEl = document.querySelector<HTMLDivElement>("#zooms");
  if (!clipEl || !zoomEl) return;
  const width = Math.max(
      600,
      document.querySelector<HTMLElement>("#timeline")?.clientWidth ?? 0,
      duration(p.kept) * timelineScale,
    ),
    factor = width / duration(p.kept);
  clipEl.style.width = zoomEl.style.width = width + "px";
  configureSelection(width, factor);
  clipEl.innerHTML = p.kept
    .map(
      (s, i) =>
        `<div draggable="true" class="clip ${selectedClip === i ? "chosen" : ""}" data-index="${i}" style="width:${(s.end - s.start) * factor}px;flex-shrink:0">${i + 1} · ${time(s.end - s.start)}</div>`,
    )
    .join("");
  const insertion = document.createElement("div");
  insertion.className = "drop-insertion";
  insertion.hidden = true;
  clipEl.append(insertion);
  let dragged = -1;
  const clearInsertion = () => (insertion.hidden = true);
  clipEl.ondragleave = (e) => {
    if (!clipEl.contains(e.relatedTarget as Node | null)) clearInsertion();
  };
  clipEl.querySelectorAll<HTMLElement>(".clip").forEach((el) => {
    const i = Number(el.dataset.index);
    el.ondragstart = (e) => {
      dragged = i;
      e.dataTransfer!.effectAllowed = "move";
      e.dataTransfer!.setData("text/plain", String(i));
    };
    el.ondragover = (e) => {
      e.preventDefault();
      if (dragged < 0) return;
      const box = el.getBoundingClientRect(),
        boundary = i + (e.clientX > box.left + box.width / 2 ? 1 : 0);
      insertion.hidden = false;
      insertion.style.left =
        Math.max(
          1,
          Math.min(width - 1, boundaries(p.kept)[boundary] * factor),
        ) + "px";
    };
    el.ondragend = clearInsertion;
    el.ondrop = (e) => {
      e.preventDefault();
      clearInsertion();
      if (dragged < 0) return;
      const box = el.getBoundingClientRect();
      change({
        ...p,
        kept: moveClip(
          p.kept,
          dragged,
          i + (e.clientX > box.left + box.width / 2 ? 1 : 0),
        ),
      });
    };
    el.onclick = (e) => {
      selectedClip = i;
      seek(
        boundaries(p.kept)[i] +
          ((e.clientX - el.getBoundingClientRect().left) /
            el.getBoundingClientRect().width) *
            (p.kept[i].end - p.kept[i].start),
      );
      drawTimeline();
    };
  });
  zoomEl.innerHTML = "";
  let offset = 0;
  p.kept.forEach((clip, index) => {
    const segmentOffset = offset;
    for (const z of p.zooms) {
      const a = Math.max(clip.start, z.start),
        b = Math.min(clip.end, z.end);
      if (b <= a) continue;
      const el = document.createElement("div");
      el.className = "zoom";
      el.style.left = (offset + a - clip.start) * factor + "px";
      el.style.width = (b - a) * factor + "px";
      el.innerHTML =
        '<span class="edge" data-edge="start"></span><span>聚焦</span><span class="edge" data-edge="end"></span>';
      el.onclick = (e) => {
        if (!(e.target as HTMLElement).dataset.edge) focusDialog(z);
      };
      el.querySelectorAll<HTMLElement>(".edge").forEach((edge) => {
        edge.onpointerdown = (e) => {
          e.preventDefault();
          e.stopPropagation();
          pause();
          const startX = e.clientX,
            edgeName = edge.dataset.edge as "start" | "end",
            original =
              segmentOffset + (edgeName === "start" ? a : b) - clip.start;
          const clipOffset = boundaries(p.kept)[index];
          let finalTime = original;
          edge.setPointerCapture(e.pointerId);
          edge.onpointermove = (event) => {
            finalTime = timelineSnap(
              original + (event.clientX - startX) / factor,
              factor,
            );
            const limited = Math.max(
              clipOffset,
              Math.min(clipOffset + clip.end - clip.start, finalTime),
            );
            if (edgeName === "start") {
              el.style.left = limited * factor + "px";
              el.style.width =
                Math.max(
                  8,
                  (segmentOffset + b - clip.start - limited) * factor,
                ) + "px";
            } else
              el.style.width =
                Math.max(
                  8,
                  (limited - (segmentOffset + a - clip.start)) * factor,
                ) + "px";
          };
          edge.onpointerup = () => {
            edge.onpointermove = null;
            edge.onpointerup = null;
            change(resizeZoom(p, z.id, index, edgeName, finalTime));
          };
        };
      });
      zoomEl.append(el);
    }
    offset += clip.end - clip.start;
  });
}
let lastFrame = performance.now();
function frame(now: number) {
  const delta = Math.min(0.15, (now - lastFrame) / 1000);
  lastFrame = now;
  if (handle && view === "editor") {
    const p = handle.project;
    if (playing && !video.seeking && video.readyState >= 2) {
      const previousSource = sourceTime(p.kept, playhead) ?? 0;
      playhead = Math.min(duration(p.kept), playhead + delta);
      const source = sourceTime(p.kept, playhead);
      if (
        source !== null &&
        (Math.abs(source - previousSource - delta) > 0.025 ||
          Math.abs(video.currentTime - source) > 0.16)
      ) {
        video.currentTime = source;
        if (video.paused && playhead < duration(p.kept))
          void video.play().catch(error);
      }
      if (playhead >= duration(p.kept)) pause();
      updateTransport();
    }
    const c = document.querySelector<HTMLCanvasElement>("#preview");
    if (c && video.readyState >= 2) {
      const camera = cameraAt(p, sourceTime(p.kept, playhead) ?? 0),
        ctx = c.getContext("2d")!,
        w = video.videoWidth / camera.scale,
        h = video.videoHeight / camera.scale,
        x = Math.max(
          0,
          Math.min(
            video.videoWidth - w,
            camera.centerX * video.videoWidth - w / 2,
          ),
        ),
        y = Math.max(
          0,
          Math.min(
            video.videoHeight - h,
            camera.centerY * video.videoHeight - h / 2,
          ),
        );
      ctx.drawImage(video, x, y, w, h, 0, 0, c.width, c.height);
    }
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
function focusDialog(existing?: Zoom) {
  if (!handle) return;
  pause();
  const p = handle.project,
    t = sourceTime(p.kept, playhead) ?? 0;
  if (existing && (t < existing.start || t > existing.end))
    video.currentTime = (existing.start + existing.end) / 2;
  let draft: Zoom = existing
    ? { ...existing }
    : {
        id: crypto.randomUUID(),
        start: Math.max(0, Math.min(p.duration - 0.04, t - 0.3)),
        end: Math.min(p.duration, t + 2),
        centerX: 0.5,
        centerY: 0.5,
        scale: 2,
        manual: true,
      };
  const dialog = document.createElement("dialog");
  dialog.innerHTML = `<h2>调整聚焦位置</h2><p>拖动画面中的方框，选择想突出的重点。</p><div class="focus-stage"><canvas width="${p.width}" height="${p.height}"></canvas><div class="focus-box"></div></div><canvas class="focus-preview" width="480" height="${Math.round((480 * p.height) / p.width)}"></canvas><label>放大倍率 <input id="focusScale" type="range" min="1.1" max="3" step="0.1" value="${draft.scale}"><span id="focusValue"></span></label><div class="row between">${existing ? '<button id="removeFocus" class="danger">删除聚焦</button>' : "<span></span>"}<div class="row"><button id="cancelFocus">取消</button><button id="applyFocus" class="primary">应用</button></div></div>`;
  document.body.append(dialog);
  dialog.showModal();
  const original = dialog.querySelector("canvas")!,
    preview = dialog.querySelector<HTMLCanvasElement>(".focus-preview")!,
    box = dialog.querySelector<HTMLDivElement>(".focus-box")!;
  const paint = () => {
    if (video.readyState < 2) return;
    const w = p.width / draft.scale,
      h = p.height / draft.scale;
    draft.centerX = Math.max(
      0.5 / draft.scale,
      Math.min(1 - 0.5 / draft.scale, draft.centerX),
    );
    draft.centerY = Math.max(
      0.5 / draft.scale,
      Math.min(1 - 0.5 / draft.scale, draft.centerY),
    );
    original.getContext("2d")!.drawImage(video, 0, 0, p.width, p.height);
    preview
      .getContext("2d")!
      .drawImage(
        video,
        draft.centerX * p.width - w / 2,
        draft.centerY * p.height - h / 2,
        w,
        h,
        0,
        0,
        preview.width,
        preview.height,
      );
    Object.assign(box.style, {
      left: (draft.centerX - 0.5 / draft.scale) * 100 + "%",
      top: (draft.centerY - 0.5 / draft.scale) * 100 + "%",
      width: 100 / draft.scale + "%",
      height: 100 / draft.scale + "%",
    });
    dialog.querySelector("#focusValue")!.textContent =
      draft.scale.toFixed(1) + "×";
  };
  video.addEventListener("seeked", paint);
  paint();
  box.onpointerdown = (e) => {
    box.setPointerCapture(e.pointerId);
    const start = {
      x: e.clientX,
      y: e.clientY,
      cx: draft.centerX,
      cy: draft.centerY,
    };
    box.onpointermove = (event) => {
      draft.centerX =
        start.cx + (event.clientX - start.x) / original.clientWidth;
      draft.centerY =
        start.cy + (event.clientY - start.y) / original.clientHeight;
      paint();
    };
    box.onpointerup = () => (box.onpointermove = null);
  };
  dialog.querySelector<HTMLInputElement>("#focusScale")!.oninput = (e) => {
    draft.scale = Number((e.target as HTMLInputElement).value);
    paint();
  };
  const close = () => {
    video.removeEventListener("seeked", paint);
    dialog.close();
    dialog.remove();
    seek(playhead);
  };
  dialog.oncancel = close;
  on("cancelFocus", close);
  on("applyFocus", () => {
    change({
      ...p,
      zooms: [
        ...p.zooms
          .filter((z) => z.id !== draft.id)
          .flatMap((z) => {
            if (z.end <= draft.start || z.start >= draft.end) return [z];
            const parts: Zoom[] = [];
            if (z.start < draft.start)
              parts.push({
                ...z,
                id: crypto.randomUUID(),
                end: draft.start,
                animationRange: z.animationRange ?? {
                  start: z.start,
                  end: z.end,
                },
              });
            if (z.end > draft.end)
              parts.push({
                ...z,
                id: crypto.randomUUID(),
                start: draft.end,
                animationRange: z.animationRange ?? {
                  start: z.start,
                  end: z.end,
                },
              });
            return parts;
          }),
        { ...draft, manual: true },
      ].sort((a, b) => a.start - b.start),
    });
    close();
  });
  on("removeFocus", () => {
    change({ ...p, zooms: p.zooms.filter((z) => z.id !== draft.id) });
    close();
  });
}
function exportDialog() {
  if (!handle) return;
  pause();
  const dialog = document.createElement("dialog");
  dialog.innerHTML =
    '<h2>导出作品</h2><p>选择适合分享的格式和清晰度。</p><label>格式 <select id="format"><option value="mp4">MP4 视频</option><option value="gif">GIF 动图（无声）</option></select></label><label>清晰度 <select id="resolution"><option value="1920">1080p</option><option value="2560">1440p</option><option value="3840">2160p</option><option value="1280">720p</option></select></label><label>帧率 <select id="fps"><option value="30">30 fps</option><option value="60">60 fps</option><option value="15">15 fps</option></select></label><label><input type="checkbox" id="exportSelection"> 仅导出当前选区</label><progress id="progress" value="0" max="100"></progress><p id="exportStatus">准备导出</p><div class="row"><button id="cancelExport">关闭</button><button id="runExport" class="primary">选择位置并导出</button><button id="reveal" hidden>查看文件</button></div>';
  document.body.append(dialog);
  dialog.showModal();
  const progress = dialog.querySelector<HTMLProgressElement>("#progress")!,
    status = dialog.querySelector("#exportStatus")!,
    start = dialog.querySelector<HTMLButtonElement>("#runExport")!,
    cancel = dialog.querySelector<HTMLButtonElement>("#cancelExport")!;
  const unsub = api.onExportProgress((value) => {
    progress.value = value <= 1 ? value * 100 : value;
    status.textContent = `正在导出 ${Math.round(progress.value)}%`;
  });
  const close = () => {
    unsub();
    dialog.close();
    dialog.remove();
  };
  dialog.oncancel = (e) => {
    e.preventDefault();
    if (exporting) void api.cancelExport();
    else close();
  };
  cancel.onclick = () => {
    if (exporting) {
      status.textContent = "正在取消…";
      void api.cancelExport().catch(error);
    } else close();
  };
  on("reveal", () => api.revealExport());
  start.onclick = async () => {
    try {
      exporting = true;
      start.disabled = true;
      cancel.textContent = "取消导出";
      await flushSave();
      const selection = dialog.querySelector<HTMLInputElement>(
        "#exportSelection",
      )!.checked
        ? { ...range }
        : undefined;
      if (selection && selection.end <= selection.start)
        throw new Error("请选择有效的导出范围。");
      const result = await api.exportProject(handle!.project, {
        format: (dialog.querySelector("#format") as HTMLSelectElement).value as
          | "mp4"
          | "gif",
        longEdge: Number(
          (dialog.querySelector("#resolution") as HTMLSelectElement).value,
        ),
        fps: Number((dialog.querySelector("#fps") as HTMLSelectElement).value),
        selection,
      });
      status.textContent = result
        ? "导出完成，已保存到所选位置。"
        : "已取消导出";
      if (result) {
        progress.value = 100;
        (dialog.querySelector("#reveal") as HTMLButtonElement).hidden = false;
      }
    } catch (e) {
      status.textContent = "导出失败，请重试。";
      error(e);
    } finally {
      exporting = false;
      start.disabled = false;
      cancel.textContent = "关闭";
    }
  };
}
window.addEventListener("keydown", (e) => {
  if (
    document.querySelector("dialog[open]") ||
    ["INPUT", "SELECT", "TEXTAREA"].includes((e.target as HTMLElement).tagName)
  )
    return;
  if (view !== "editor" || !handle || exporting) return;
  if (e.ctrlKey && e.key.toLowerCase() === "b") {
    e.preventDefault();
    change({ ...handle.project, kept: split(handle.project.kept, playhead) });
  }
  if (e.ctrlKey && e.key.toLowerCase() === "z") {
    e.preventDefault();
    history(e.shiftKey);
  }
  if (e.ctrlKey && e.key.toLowerCase() === "y") {
    e.preventDefault();
    history(true);
  }
  if (e.code === "Space") {
    e.preventDefault();
    document.getElementById("play")?.click();
  }
});
renderRecord();
void refreshSources().catch(error);
