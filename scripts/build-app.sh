#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$(pwd)/dist/Demo Recorder.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DemoRecorder "$APP/Contents/MacOS/DemoRecorder"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "$APP"
