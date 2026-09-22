export type Span = { start: number; end: number };
export type Rect = { x: number; y: number; width: number; height: number };
export type Sample = { time: number; x: number; y: number; clicked: boolean };
export type Zoom = Span & {
  id: string;
  centerX: number;
  centerY: number;
  scale: number;
  manual: boolean;
  animationRange?: Span;
};
export type Project = {
  version: 1;
  id: string;
  name: string;
  source: string;
  duration: number;
  width: number;
  height: number;
  hasAudio: boolean;
  kept: Span[];
  zooms: Zoom[];
  samples: Sample[];
  autoZoom: boolean;
};
export type Camera = { centerX: number; centerY: number; scale: number };
export type ExportSettings = {
  format: "mp4" | "gif";
  longEdge: number;
  fps: number;
  selection?: Span;
};
export type CaptureSource = {
  id: string;
  title: string;
  kind: "screen" | "window";
  thumbnail: string;
  displayId: string;
  bounds: Rect;
};
export type CaptureOptions = { sourceId: string; region?: Rect };
export type ProjectHandle = {
  project: Project;
  mediaUrl: string;
  warnings?: string[];
};
export type RecentProject = { id: string; name: string; modified: string };
export interface DesktopAPI {
  platform: string;
  sources(): Promise<CaptureSource[]>;
  chooseRegion(sourceId: string): Promise<Rect | null>;
  prepareCapture(options: CaptureOptions): Promise<{ token: string }>;
  captureStarted(token: string, epoch: number): Promise<{ warnings: string[] }>;
  appendCapture(token: string, chunk: ArrayBuffer): Promise<void>;
  finishCapture(token: string): Promise<ProjectHandle>;
  abortCapture(token: string): Promise<void>;
  openProject(): Promise<ProjectHandle | null>;
  openRecent(id: string): Promise<ProjectHandle>;
  importVideo(): Promise<ProjectHandle | null>;
  recent(): Promise<RecentProject[]>;
  saveProject(project: Project): Promise<void>;
  exportProject(
    project: Project,
    settings: ExportSettings,
  ): Promise<string | null>;
  cancelExport(): Promise<void>;
  openMore(): Promise<void>;
  revealExport(): Promise<void>;
  closeReady(): Promise<void>;
  onCloseRequest(callback: () => void): () => void;
  onStopRequest(callback: () => void): () => void;
  onExportProgress(callback: (progress: number) => void): () => void;
}
declare global {
  interface Window {
    jdad: DesktopAPI;
    regionAPI: {
      initial(): Promise<{ width: number; height: number }>;
      finish(rect: Rect | null): Promise<void>;
    };
  }
}
