#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building Flow (Release)..."
xcodebuild -project Flow.xcodeproj \
  -scheme Flow \
  -configuration Release \
  -derivedDataPath build \
  build \
  -quiet

APP_PATH="build/Build/Products/Release/Flow.app"
echo "==> Build complete: $APP_PATH"
echo ""
echo "Run with: open $APP_PATH"
