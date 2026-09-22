#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# A hash-only ad-hoc signature changes identity on every build and breaks TCC.
SIGNING_IDENTITY="${DEMO_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    IDENTITIES=()
    while IFS= read -r identity; do
        IDENTITIES+=("$identity")
    done < <(security find-identity -v -p codesigning | sed -nE '/"(Apple Development:|Developer ID Application:)/s/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}).*/\1/p')
    if [ "${#IDENTITIES[@]}" -ne 1 ]; then
        echo 'Set DEMO_SIGNING_IDENTITY to one valid Apple Development or Developer ID Application signing identity.' >&2
        echo 'Ad-hoc signing is not used because it invalidates recording permissions after updates.' >&2
        exit 1
    fi
    SIGNING_IDENTITY="${IDENTITIES[0]}"
fi
if [ "$SIGNING_IDENTITY" = '-' ]; then
    echo 'Ad-hoc signing is not supported for recording builds.' >&2
    exit 1
fi
swift build -c release
OUTPUT_DIR="${DEMO_OUTPUT_DIR:-$(pwd)/dist}"
APP="$OUTPUT_DIR/Demo Recorder.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DemoRecorder "$APP/Contents/MacOS/DemoRecorder"
ICONSET="$OUTPUT_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    twice=$((size * 2))
    if [ "$size" != 512 ]; then
        sips -z "$twice" "$twice" "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
./scripts/check-signing.sh "$APP"
echo "$APP"
