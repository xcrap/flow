#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "==> Testing AFCore..."
cd Packages/AFCore && swift test --quiet
cd ../..

echo "==> Testing AFCanvas..."
cd Packages/AFCanvas && swift test --quiet
cd ../..

echo "==> Testing AFAgent..."
cd Packages/AFAgent && swift test --quiet
cd ../..

echo "==> All tests passed!"
