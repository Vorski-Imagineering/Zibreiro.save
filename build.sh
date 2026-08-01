#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
ARCH="$(uname -m)"
BUILD_DIR="$ROOT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/Rothko.saver"

mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

swiftc \
  -sdk "$SDK_PATH" \
  -target "${ARCH}-apple-macosx${DEPLOYMENT_TARGET}" \
  -parse-as-library \
  "$ROOT_DIR/Sources/RothkoScreenSaverView.swift" \
  -o "$BUNDLE_DIR/Contents/MacOS/Rothko" \
  -framework ScreenSaver \
  -framework WebKit \
  -Xlinker -bundle \
  -Xlinker -undefined \
  -Xlinker dynamic_lookup

cp "$ROOT_DIR/Supporting Files/Info.plist" "$BUNDLE_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/index.html" "$BUNDLE_DIR/Contents/Resources/index.html"

plutil -lint "$BUNDLE_DIR/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null

echo "Built $BUNDLE_DIR"
echo "SDK: macOS $SDK_VERSION ($SDK_PATH)"
echo "Architecture: $ARCH"
