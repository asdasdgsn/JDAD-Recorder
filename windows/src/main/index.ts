import {
  app,
  BrowserWindow,
  desktopCapturer,
  dialog,
  ipcMain,
  Menu,
  net,
  protocol,
  screen,
  session,
  shell,
  Tray,
} from "electron";
import type { DesktopCapturerSource } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { copyFile, access, realpath, unlink } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { ProjectStore } from "./store";
import { CaptureSession } from "./capture";
import { windowBounds } from "./native";
import {
  exportMedia,
  probeMedia,
  finalizeRecording,
  mediaBinaries,
} from "./media";
import { validateProject } from "../core";
import type {
  CaptureSource,
  CaptureOptions,
  Rect,
  Project,
  ExportSettings,
} from "../shared/types";
app.setName("JDAD Recorder");
protocol.registerSchemesAsPrivileged([
  {
    scheme: "jdad-media",
    privileges: {
      standard: true,
      secure: true,
      stream: true,
      supportFetchAPI: true,
    },
  },
]);
let main: BrowserWindow;
let tray: Tray;
let store: ProjectStore;
let capture: CaptureSession | undefined;
let chosen: DesktopCapturerSource | undefined;
let exportController: AbortController | undefined;
let lastExport = "";
let quitting = false;
let quitAfterCapture = false;
let regionWindow: BrowserWindow | undefined;
let sourceMap = new Map<
  string,
  { native: DesktopCapturerSource; info: CaptureSource }
>();
const assets = path.join(__dirname, "../assets");
const show = () => {
  if (main && !main.isDestroyed()) {
    main.show();
    main.focus();
  }
};
const idle = () => {
  if (capture || exportController) throw new Error("请先结束录制或导出。");
};
function validRect(rect: Rect) {
  return (
    rect &&
    ["x", "y", "width", "height"].every((k) =>
      Number.isFinite(rect[k as keyof Rect]),
    ) &&
    rect.x >= 0 &&
    rect.y >= 0 &&
    rect.width > 0 &&
    rect.height > 0 &&
    rect.x + rect.width <= 1.000001 &&
    rect.y + rect.height <= 1.000001
  );
}
function guard(event: Electron.IpcMainInvokeEvent) {
  if (
    event.sender !== main.webContents ||
    event.senderFrame !== main.webContents.mainFrame
  )
    throw new Error("无效请求来源。");
}
function handle(name: string, fn: (...args: any[]) => unknown) {
  ipcMain.handle(name, (event, ...args) => {
    guard(event);
    return fn(...args);
  });
}
async function listSources() {
  const displays = screen.getAllDisplays();
  const sources = await desktopCapturer.getSources({
    types: ["screen", "window"],
    thumbnailSize: { width: 320, height: 180 },
    fetchWindowIcons: false,
  });
  sourceMap = new Map();
  for (const source of sources) {
    if (
      source.id === main.getMediaSourceId() ||
      source.id === regionWindow?.getMediaSourceId()
    )
      continue;
    const kind = source.id.startsWith("screen:") ? "screen" : "window";
    const d =
      displays.find((d) => String(d.id) === source.display_id) ??
      screen.getPrimaryDisplay();
    let bounds: Rect = d.bounds;
    if (process.platform === "win32") {
      bounds =
        kind === "window"
          ? (windowBounds(source.id) ?? { x: 0, y: 0, width: 0, height: 0 })
          : screen.dipToScreenRect(null, d.bounds);
    }
    if (bounds.width <= 0 || bounds.height <= 0) continue;
    const info: CaptureSource = {
      id: source.id,
      title: source.name,
      kind,
      thumbnail: source.thumbnail.toDataURL(),
      displayId: source.display_id,
      bounds,
    };
    sourceMap.set(source.id, { native: source, info });
  }
  return [...sourceMap.values()].map((s) => s.info);
}
async function chooseRegion(id: string): Promise<Rect | null> {
  idle();
  if (regionWindow) throw new Error("请先完成区域选择。");
  const source = sourceMap.get(id);
  if (!source || source.info.kind !== "screen")
    throw new Error("请先选择屏幕。");
  const display =
    screen
      .getAllDisplays()
      .find((d) => String(d.id) === source.info.displayId) ??
    screen.getPrimaryDisplay();
  return new Promise((resolve) => {
    let settled = false;
    const win = new BrowserWindow({
      ...display.bounds,
      frame: false,
      transparent: true,
      alwaysOnTop: true,
      skipTaskbar: true,
      resizable: false,
      movable: false,
      hasShadow: false,
      show: false,
      webPreferences: {
        preload: path.join(__dirname, "preload.cjs"),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    regionWindow = win;
    win.setContentProtection(true);
    const finish = (rect: Rect | null) => {
      if (settled) return;
      settled = true;
      ipcMain.removeHandler("region-initial");
      ipcMain.removeHandler("region-finish");
      regionWindow = undefined;
      if (!win.isDestroyed()) win.close();
      show();
      resolve(rect);
    };
    ipcMain.handle("region-initial", (e) => {
      if (e.sender !== win.webContents) throw new Error("无效来源");
      return { width: display.bounds.width, height: display.bounds.height };
    });
    ipcMain.handle("region-finish", (e, rect) => {
      if (e.sender !== win.webContents) throw new Error("无效来源");
      if (
        rect !== null &&
        (!validRect(rect) ||
          rect.width * display.bounds.width < 32 ||
          rect.height * display.bounds.height < 32)
      )
        throw new Error("区域至少需要 32 × 32 像素。");
      finish(rect);
    });
    win.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
    win.webContents.on("will-navigate", (e) => e.preventDefault());
    win.once("closed", () => finish(null));
    win.once("ready-to-show", () => {
      main.hide();
      win.show();
      win.focus();
    });
    win
      .loadFile(path.join(__dirname, "region/index.html"))
      .catch(() => finish(null));
  });
}
function token(value: string) {
  if (!capture || capture.token !== value) throw new Error("录制会话已失效。");
  return capture;
}
async function openRoot(root: string) {
  try {
    return await store.open(root);
  } catch (error) {
    const canonical = await realpath(root);
    try {
      await access(path.join(canonical, "recording.inprogress"));
    } catch {
      throw error;
    }
    const media = await realpath(path.join(canonical, "media"));
    if (path.dirname(media) !== canonical)
      throw new Error("恢复素材必须位于工程目录内。");
    const raw = await realpath(path.join(media, "recording.webm"));
    if (path.dirname(raw) !== media)
      throw new Error("恢复素材必须位于工程目录内。");
    const temporary = path.join(media, "recovered-" + randomUUID() + ".webm");
    try {
      const meta = await finalizeRecording(raw, temporary);
      const source = "media/" + path.basename(temporary);
      const project: Project = {
        version: 1,
        id: randomUUID(),
        name: "恢复的录制",
        source,
        ...meta,
        kept: [{ start: 0, end: meta.duration }],
        samples: [],
        zooms: [],
        autoZoom: true,
      };
      return await store.complete(canonical, project);
    } catch (e) {
      await unlink(temporary).catch(() => {});
      throw e;
    }
  }
}
async function setup() {
  store = new ProjectStore(
    app.getPath("userData"),
    path.join(app.getPath("videos"), "JDAD Recorder"),
  );
  protocol.handle("jdad-media", (request) => {
    const url = new URL(request.url);
    const file =
      url.hostname === "video"
        ? store.mediaPath(url.pathname.slice(1))
        : undefined;
    if (!file) return new Response("Not found", { status: 404 });
    return net.fetch(pathToFileURL(file).href, { headers: request.headers });
  });
  main = new BrowserWindow({
    width: 1280,
    height: 840,
    minWidth: 1040,
    minHeight: 720,
    backgroundColor: "#141718",
    title: "JDAD Recorder",
    icon: path.join(assets, "icon.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.cjs"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      backgroundThrottling: false,
    },
  });
  main.webContents.setWindowOpenHandler(() => ({ action: "deny" }));
  main.webContents.on("will-navigate", (e) => e.preventDefault());
  main.on("close", (e) => {
    if (main.webContents.isCrashed()) {
      quitting = true;
      exportController?.abort();
      return;
    }
    if (!quitting) {
      e.preventDefault();
      if (capture) main.hide();
      else if (exportController) {
        show();
      } else main.webContents.send("close-request");
    }
  });
  main.webContents.on("render-process-gone", () => {
    const current = capture;
    capture = undefined;
    chosen = undefined;
    current?.abort().catch(() => {});
    exportController?.abort();
  });
  session.defaultSession.setPermissionCheckHandler(
    (contents, permission) =>
      contents === main.webContents &&
      ["media", "display-capture"].includes(permission),
  );
  session.defaultSession.setPermissionRequestHandler(
    (contents, permission, callback) =>
      callback(
        contents === main.webContents &&
          ["media", "display-capture"].includes(permission),
      ),
  );
  session.defaultSession.setDisplayMediaRequestHandler((request, callback) => {
    if (request.frame === main.webContents.mainFrame && chosen && capture)
      callback({ video: chosen, audio: undefined });
    else callback({});
  });
  handle("close-ready", async () => {
    idle();
    await store.flush();
    quitting = true;
    app.quit();
  });
  handle("sources", listSources);
  handle("choose-region", chooseRegion);
  handle("prepare-capture", async (options: CaptureOptions) => {
    idle();
    await Promise.all(
      Object.values(mediaBinaries()).map((file) => access(file)),
    );
    if (!options || typeof options.sourceId !== "string")
      throw new Error("请选择录制来源。");
    await listSources();
    const source = sourceMap.get(options.sourceId);
    if (!source) throw new Error("所选窗口已关闭，请重新选择。");
    if (
      options.region &&
      (source.info.kind !== "screen" || !validRect(options.region))
    )
      throw new Error("无效录制区域。");
    capture = await CaptureSession.create(options, source.info, store);
    chosen = source.native;
    return { token: capture.token };
  });
  handle("capture-started", (id: string, epoch: number) => {
    const result = token(id).start(epoch);
    main.hide();
    if (quitAfterCapture)
      setImmediate(() => main.webContents.send("stop-request"));
    return result;
  });
  handle("append-capture", (id: string, chunk: ArrayBuffer) =>
    token(id).append(chunk),
  );
  handle("finish-capture", async (id: string) => {
    const current = token(id);
    let completed = false;
    try {
      const result = await current.finish();
      completed = true;
      return result;
    } finally {
      if (capture === current) {
        capture = undefined;
        chosen = undefined;
      }
      if (completed && quitAfterCapture) {
        await store.flush();
        quitting = true;
        app.quit();
      } else {
        quitAfterCapture = false;
        show();
      }
    }
  });
  handle("abort-capture", async (id: string) => {
    const current = token(id);
    try {
      await current.abort();
    } finally {
      capture = undefined;
      chosen = undefined;
      show();
    }
  });
  handle("recent", () => store.recent());
  handle("open-recent", (id: string) => {
    idle();
    return store.openRecent(id);
  });
  handle("open-project", async () => {
    idle();
    const result = await dialog.showOpenDialog(main, {
      title: "打开 JDAD Recorder 工程文件夹",
      properties: ["openDirectory"],
    });
    return result.canceled ? null : openRoot(result.filePaths[0]);
  });
  handle("import-video", async () => {
    idle();
    const result = await dialog.showOpenDialog(main, {
      title: "导入视频",
      properties: ["openFile"],
      filters: [{ name: "视频", extensions: ["mp4", "mov", "webm", "mkv"] }],
    });
    if (result.canceled) return null;
    const input = result.filePaths[0];
    const meta = await probeMedia(input);
    const root = await store.createFolder();
    const source = "media/original" + path.extname(input).toLowerCase();
    await copyFile(input, path.join(root, source));
    return store.complete(root, {
      version: 1,
      id: randomUUID(),
      name: path.basename(input, path.extname(input)),
      source,
      ...meta,
      kept: [{ start: 0, end: meta.duration }],
      zooms: [],
      samples: [],
      autoZoom: true,
    });
  });
  handle("save-project", (project: Project) => store.save(project));
  handle(
    "export-project",
    async (project: Project, settings: ExportSettings) => {
      idle();
      validateProject(project);
      if (!settings || !["mp4", "gif"].includes(settings.format))
        throw new Error("无效导出格式。");
      await store.save(project);
      const controller = new AbortController();
      exportController = controller;
      try {
        const result = await dialog.showSaveDialog(main, {
          title: "导出视频",
          defaultPath: path.join(
            app.getPath("videos"),
            project.name.replace(/[<>:"/\\|?*\x00-\x1f]/g, "_") +
              "." +
              settings.format,
          ),
          filters: [
            {
              name: settings.format.toUpperCase(),
              extensions: [settings.format],
            },
          ],
        });
        if (result.canceled || !result.filePath) return null;
        await store.assertExportDestination(result.filePath);
        await exportMedia(
          project,
          store.active!.sourcePath,
          result.filePath,
          settings,
          controller.signal,
          (p) => {
            if (!main.isDestroyed())
              main.webContents.send("export-progress", p);
          },
        );
        lastExport = result.filePath;
        return lastExport;
      } catch (error) {
        if (controller.signal.aborted) return null;
        throw error;
      } finally {
        exportController = undefined;
      }
    },
  );
  handle("cancel-export", () => {
    exportController?.abort();
  });
  handle("open-more", () =>
    shell.openExternal("https://jdauto.joyapp.jd.com/"),
  );
  handle("reveal-export", () => {
    if (lastExport) shell.showItemInFolder(lastExport);
  });
  tray = new Tray(path.join(assets, "icon.png"));
  tray.setToolTip("JDAD Recorder");
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: "打开 JDAD Recorder", click: show },
      {
        label: "停止录制",
        click: () => {
          show();
          main.webContents.send("stop-request");
        },
      },
      { type: "separator" },
      {
        label: "退出",
        click: () => {
          if (capture) {
            quitAfterCapture = true;
            show();
            main.webContents.send("stop-request");
          } else app.quit();
        },
      },
    ]),
  );
  tray.on("click", show);
  Menu.setApplicationMenu(null);
  await main.loadFile(path.join(__dirname, "renderer/index.html"));
}
if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on("second-instance", show);
  app
    .whenReady()
    .then(setup)
    .catch((error) => {
      dialog.showErrorBox("启动失败", String(error));
      quitting = true;
      app.quit();
    });
}
app.on("window-all-closed", () => {
  if (!capture) app.quit();
});
app.on("before-quit", (event) => {
  if (quitting) return;
  event.preventDefault();
  if (capture) {
    quitAfterCapture = true;
    show();
    main.webContents.send("stop-request");
    return;
  }
  if (exportController) {
    show();
    return;
  }
  if (main && !main.isDestroyed() && !main.webContents.isCrashed())
    main.webContents.send("close-request");
  else {
    quitting = true;
    app.quit();
  }
});
