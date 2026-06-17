#!/usr/bin/env bash
# Fetch the native dependencies for KokoroSpeechEngine. These are intentionally
# NOT committed to git (≈470 MB total); run this once after cloning. Everything
# lands under Vendor/ where the Xcode project and the app expect it:
#
#   Vendor/sherpa-onnx.xcframework      static sherpa-onnx (linked)
#   Vendor/onnxruntime/…dylib           onnxruntime runtime (linked + embedded)
#   Vendor/kokoro/                      Kokoro model bundle (read at runtime)
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REL="https://github.com/k2-fsa/sherpa-onnx/releases/download"
SHERPA_VER="v1.13.3"
ORT_VER="1.24.4"

fetch() { # url  out
  echo "↓ $(basename "$1")"
  curl -fL --progress-bar -o "$2" "$1"
}

# 1) sherpa-onnx static xcframework
if [ ! -f "$DIR/sherpa-onnx.xcframework/macos-arm64_x86_64/libsherpa-onnx.a" ]; then
  fetch "$REL/$SHERPA_VER/sherpa-onnx-$SHERPA_VER-macos-xcframework-static.tar.bz2" "$DIR/sherpa.tar.bz2"
  tar xjf "$DIR/sherpa.tar.bz2" -C "$DIR"
  mv "$DIR/sherpa-onnx-$SHERPA_VER-macos-xcframework-static/sherpa-onnx.xcframework" "$DIR/sherpa-onnx.xcframework"
  rm -rf "$DIR/sherpa-onnx-$SHERPA_VER-macos-xcframework-static" "$DIR/sherpa.tar.bz2"
else echo "✓ sherpa-onnx.xcframework present"; fi

# 2) onnxruntime dylib (matching the sherpa build)
if [ ! -f "$DIR/onnxruntime/libonnxruntime.$ORT_VER.dylib" ]; then
  fetch "$REL/$SHERPA_VER/sherpa-onnx-$SHERPA_VER-onnxruntime-$ORT_VER-osx-arm64-shared.tar.bz2" "$DIR/ort.tar.bz2"
  mkdir -p "$DIR/onnxruntime"
  tar xjf "$DIR/ort.tar.bz2" -C "$DIR/onnxruntime" --strip-components=2 \
    "sherpa-onnx-$SHERPA_VER-onnxruntime-$ORT_VER-osx-arm64-shared/lib/libonnxruntime.$ORT_VER.dylib"
  rm -f "$DIR/ort.tar.bz2"
else echo "✓ onnxruntime dylib present"; fi

# 3) Kokoro multi-lang v1.0 model bundle (≈394 MB extracted)
if [ ! -f "$DIR/kokoro/model.onnx" ]; then
  fetch "$REL/tts-models/kokoro-multi-lang-v1_0.tar.bz2" "$DIR/kokoro.tar.bz2"
  tar xjf "$DIR/kokoro.tar.bz2" -C "$DIR"
  mv "$DIR/kokoro-multi-lang-v1_0" "$DIR/kokoro"
  rm -f "$DIR/kokoro.tar.bz2"
else echo "✓ kokoro model present"; fi

echo "Done. Native deps ready under $DIR"
