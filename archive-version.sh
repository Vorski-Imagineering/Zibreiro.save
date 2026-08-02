#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
ALGORITHM_VERSION="${1:-}"

case "$ALGORITHM_VERSION" in
  1) ALGORITHM_NAME="WebGL sRGB Dither"; ALGORITHM_SLUG="WebGL-sRGB-Dither" ;;
  2) ALGORITHM_NAME="Shadow Range"; ALGORITHM_SLUG="Shadow-Range" ;;
  3) ALGORITHM_NAME="Six-Bit Display Dither (Rejected)"; ALGORITHM_SLUG="Six-Bit-Display-Dither-Rejected" ;;
  4) ALGORITHM_NAME="Blue-Noise Texture"; ALGORITHM_SLUG="Blue-Noise-Texture" ;;
  5) ALGORITHM_NAME="Four-Code Blue Noise"; ALGORITHM_SLUG="Four-Code-Blue-Noise" ;;
  6) ALGORITHM_NAME="Protected Black"; ALGORITHM_SLUG="Protected-Black" ;;
  7) ALGORITHM_NAME="Side-by-Side Shadow Diagnostics (Rejected)"; ALGORITHM_SLUG="Side-by-Side-Shadow-Diagnostics-Rejected" ;;
  *)
    echo "Usage: $0 <algorithm 1-7>" >&2
    exit 2
    ;;
esac

if ! xcrun --sdk macosx --find metal >/dev/null 2>&1; then
  if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  else
    echo "The Metal compiler is unavailable; select a full Xcode developer directory." >&2
    exit 3
  fi
fi

ZIBREIRO_ALGORITHM_VERSION="$ALGORITHM_VERSION" "$ROOT_DIR/build.sh"

BUILD_NUMBER="$(plutil -extract CFBundleVersion raw "$ROOT_DIR/build/Zibreiro.saver/Contents/Info.plist")"
PADDED_VERSION="$(printf '%03d' "$ALGORITHM_VERSION")"
ARCHIVE_DIR="$ROOT_DIR/build/versions"
ARCHIVE_NAME="Zibreiro-A${PADDED_VERSION}-${ALGORITHM_SLUG}-B${BUILD_NUMBER}.saver"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_NAME"

mkdir -p "$ARCHIVE_DIR"
if [[ -e "$ARCHIVE_PATH" ]]; then
  echo "Refusing to overwrite archived version: $ARCHIVE_PATH" >&2
  exit 4
fi

ditto "$ROOT_DIR/build/Zibreiro.saver" "$ARCHIVE_PATH"
plutil -replace CFBundleDisplayName -string "Zibreiro — A${PADDED_VERSION} ${ALGORITHM_NAME}" "$ARCHIVE_PATH/Contents/Info.plist"
plutil -replace CFBundleName -string "Zibreiro-A${PADDED_VERSION}" "$ARCHIVE_PATH/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.example.Zibreiro.a${PADDED_VERSION}" "$ARCHIVE_PATH/Contents/Info.plist"
plutil -insert ZibreiroAlgorithmName -string "$ALGORITHM_NAME" "$ARCHIVE_PATH/Contents/Info.plist"
codesign --force --deep --sign - "$ARCHIVE_PATH" >/dev/null
codesign --verify --deep --strict "$ARCHIVE_PATH"

echo "Archived $ARCHIVE_PATH"
