#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
ALGORITHM_VERSION="${ZIBREIRO_ALGORITHM_VERSION:-6}"
ARCH="$(uname -m)"
BUILD_DIR="$ROOT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/Zibreiro.saver"
METAL_AIR="$BUILD_DIR/ZibreiroShaders.air"
METAL_LIBRARY="$BUILD_DIR/default.metallib"
MODULE_CACHE_PATH="${ZIBREIRO_MODULE_CACHE_PATH:-/tmp/zibreiro-metal-module-cache}"

mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_CACHE_PATH"

case "$ALGORITHM_VERSION" in
  1|2|3|4|5|6|7) ;;
  *) echo "Unsupported ZIBREIRO_ALGORITHM_VERSION: $ALGORITHM_VERSION" >&2; exit 2 ;;
esac

# Command Line Tools do not include these compilers. This explicit check keeps
# a partial saver from being mistaken for a Metal build.
xcrun --sdk macosx metal -fmodules-cache-path="$MODULE_CACHE_PATH" -D "ZIBREIRO_ALGORITHM_VERSION=$ALGORITHM_VERSION" -c "$ROOT_DIR/Shaders/ZibreiroShaders.metal" -o "$METAL_AIR"
xcrun --sdk macosx metallib "$METAL_AIR" -o "$METAL_LIBRARY"

mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp "$METAL_LIBRARY" "$BUNDLE_DIR/Contents/Resources/default.metallib"

swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE_PATH" \
  -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
  -parse-as-library \
  "$ROOT_DIR/Sources/ZibreiroScreenSaverView.swift" \
  "$ROOT_DIR/Sources/MetalRenderer.swift" \
  "$ROOT_DIR/Sources/ZibreiroUniforms.swift" \
  -o "$BUNDLE_DIR/Contents/MacOS/Zibreiro" \
  -framework ScreenSaver \
  -framework Metal \
  -framework MetalKit \
  -Xlinker -bundle \
  -Xlinker -undefined \
  -Xlinker dynamic_lookup

cp "$ROOT_DIR/Supporting Files/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
plutil -replace ZibreiroAlgorithmVersion -integer "$ALGORITHM_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
# Kept as a legacy visual reference; it is not loaded or linked by the saver.
cp "$ROOT_DIR/Resources/index.html" "$BUNDLE_DIR/Contents/Resources/index.html"
cp "$ROOT_DIR/Resources/blue-noise-128.raw" "$BUNDLE_DIR/Contents/Resources/blue-noise-128.raw"

plutil -lint "$BUNDLE_DIR/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null

echo "Built $BUNDLE_DIR"
echo "SDK: macOS $SDK_VERSION ($SDK_PATH)"
echo "Architecture: $ARCH"
echo "Algorithm: $ALGORITHM_VERSION"
