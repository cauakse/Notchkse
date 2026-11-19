#!/bin/zsh
# Compila em Release e instala o Notchkse em /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Notchkse.xcodeproj -scheme Notchkse -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build | grep -E "error:|BUILD" || true
pkill -x Notchkse 2>/dev/null || true
rm -rf /Applications/Notchkse.app
cp -R build/Build/Products/Release/Notchkse.app /Applications/
open /Applications/Notchkse.app
echo "Notchkse instalado em /Applications"
