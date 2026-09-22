#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${1:-$PWD/dist/v0.4.2/JDAD Recorder.app}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
./scripts/check-signing.sh "$APP"
STAGE=$(mktemp -d /tmp/jdad-installer.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/JDAD Recorder.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'GUIDE'
JDAD Recorder · 团队测试版

适用：Apple Silicon Mac（M 系列芯片），macOS 15 或更新版本。

安装
1. 退出旧版 Demo Recorder / JDAD Recorder。
2. 将 JDAD Recorder.app 拖入 Applications（应用程序）。
3. 从“应用程序”打开 JDAD Recorder，使用完安装包后推出磁盘。

首次录制需允许“录屏与系统录音”权限。不勾选“录制麦克风”即可无声录屏。
支持屏幕、窗口、指定区域录制，自动操作聚焦、剪辑以及 MP4/GIF 导出。
已有工程继续兼容；视频仍保存在“影片 / Demo Recorder”，不上传到云端。

此包使用 Apple Development 开发签名，尚未进行 Developer ID 签名和 Apple 公证。
其他 Mac 可能被系统阻止打开；它不是已完成正式分发认证的安装包。
如系统阻止，请联系维护者提供公证版本，不需要关闭系统安全保护。

旧版升级
仅更换应用名，内部标识保留。避免同时运行新旧应用。
现有录屏授权通常可沿用，系统权限列表可能仍显示旧名称。
GUIDE
OUTPUT="$PWD/dist/JDAD-Recorder-${VERSION}-Mac-arm64.dmg"
hdiutil create -volname "JDAD Recorder $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
shasum -a 256 "$OUTPUT" > "$OUTPUT.sha256"
echo "$OUTPUT"
