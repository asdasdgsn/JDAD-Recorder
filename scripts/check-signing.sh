#!/bin/bash
set -euo pipefail
APP="${1:?Usage: check-signing.sh /path/to/app}"
codesign --verify --strict "$APP"
DETAILS="$(codesign -d -r- --verbose=4 "$APP" 2>&1)"
if [[ "$DETAILS" == *"Signature=adhoc"* || "$DETAILS" == *"designated => cdhash"* || "$DETAILS" == *"TeamIdentifier=not set"* || "$DETAILS" != *"TeamIdentifier="* ]]; then
    echo 'FAIL: application has no stable certificate identity; rebuilding can invalidate macOS recording permission.' >&2
    exit 1
fi
echo 'PASS: certificate-backed signing identity verified.'
