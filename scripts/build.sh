#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building AgentFlow (Release)..."
xcodebuild -project AgentFlow.xcodeproj \
  -scheme AgentFlow \
  -configuration Release \
  -derivedDataPath build \
  build \
  -quiet

APP_PATH="build/Build/Products/Release/AgentFlow.app"
echo "==> Build complete: $APP_PATH"
echo ""
echo "Run with: open $APP_PATH"
