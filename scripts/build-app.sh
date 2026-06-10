#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/PerformanceMonitor.app"
CONTENTS_DIR="$APP_DIR/Contents"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp ".build/release/PerformanceMonitor" "$CONTENTS_DIR/MacOS/PerformanceMonitor"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "已生成：$APP_DIR"
