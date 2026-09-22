import { contextBridge, ipcRenderer } from "electron";
import type { DesktopAPI, Rect } from "./shared/types";
const listener = (event: string, callback: (...args: any[]) => void) => {
  const receive = (_event: Electron.IpcRendererEvent, ...args: any[]) =>
    callback(...args);
  ipcRenderer.on(event, receive);
  return () => ipcRenderer.removeListener(event, receive);
};
const api: DesktopAPI = {
  platform: process.platform,
  sources: () => ipcRenderer.invoke("sources"),
  chooseRegion: (id) => ipcRenderer.invoke("choose-region", id),
  prepareCapture: (options) => ipcRenderer.invoke("prepare-capture", options),
  captureStarted: (token, epoch) =>
    ipcRenderer.invoke("capture-started", token, epoch),
  appendCapture: (token, chunk) =>
    ipcRenderer.invoke("append-capture", token, chunk),
  finishCapture: (token) => ipcRenderer.invoke("finish-capture", token),
  abortCapture: (token) => ipcRenderer.invoke("abort-capture", token),
  openProject: () => ipcRenderer.invoke("open-project"),
  openRecent: (id) => ipcRenderer.invoke("open-recent", id),
  importVideo: () => ipcRenderer.invoke("import-video"),
  recent: () => ipcRenderer.invoke("recent"),
  saveProject: (project) => ipcRenderer.invoke("save-project", project),
  exportProject: (project, settings) =>
    ipcRenderer.invoke("export-project", project, settings),
  cancelExport: () => ipcRenderer.invoke("cancel-export"),
  openMore: () => ipcRenderer.invoke("open-more"),
  revealExport: () => ipcRenderer.invoke("reveal-export"),
  closeReady: () => ipcRenderer.invoke("close-ready"),
  onCloseRequest: (callback) => listener("close-request", callback),
  onStopRequest: (callback) => listener("stop-request", callback),
  onExportProgress: (callback) => listener("export-progress", callback),
};
contextBridge.exposeInMainWorld("jdad", api);
contextBridge.exposeInMainWorld("regionAPI", {
  initial: () => ipcRenderer.invoke("region-initial"),
  finish: (rect: Rect | null) => ipcRenderer.invoke("region-finish", rect),
});
