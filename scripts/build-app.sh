#!/usr/bin/env bash
# Build "Claude Notch.app". Usage: scripts/build-app.sh [--universal] [--install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="Claude Notch"
EXECUTABLE="ClaudeNotch"
OUT_DIR="$ROOT/build"
APP="$OUT_DIR/$APP_NAME.app"

UNIVERSAL=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --install) INSTALL=1 ;;
    -h|--help)
      echo "Usage: $0 [--universal] [--install]"
      exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

BUILD_ARGS=(-c release)
if [[ "$UNIVERSAL" == "1" ]]; then
  BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build ${BUILD_ARGS[*]}"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/$EXECUTABLE"
if [[ ! -x "$BIN" ]]; then
  echo "error: built binary not found at $BIN" >&2
  exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Ad-hoc signing"
codesign --force --sign - "$APP"
codesign --verify --verbose=1 "$APP" || true

if [[ "$INSTALL" == "1" ]]; then
  echo "==> Installing to /Applications"
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  echo "Installed /Applications/$APP_NAME.app"
fi

echo "Done: $APP"
