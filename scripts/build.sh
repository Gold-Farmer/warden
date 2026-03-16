#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Warden"
APP_BUNDLE="$PROJECT_ROOT/.build/app/$APP_NAME.app"
CONFIG="${1:-debug}"

case "$CONFIG" in
    debug)   SWIFT_CONFIG="debug" ;;
    release) SWIFT_CONFIG="release" ;;
    *)       echo "Usage: $0 [debug|release] [--run]"; exit 1 ;;
esac

# ── Build ──────────────────────────────────────────────
echo "==> swift build ($SWIFT_CONFIG)..."
swift build -c "$SWIFT_CONFIG" --package-path "$PROJECT_ROOT"

BINARY="$PROJECT_ROOT/.build/$SWIFT_CONFIG/$APP_NAME"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: binary not found at $BINARY"
    exit 1
fi

# ── Package .app bundle ───────────────────────────────
echo "==> Packaging $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.warden.app</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "==> $APP_BUNDLE"

# ── Launch ─────────────────────────────────────────────
if [[ "${2:-}" == "--run" ]]; then
    echo "==> Launching..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.5
    open "$APP_BUNDLE"
fi
