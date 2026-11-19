#!/bin/zsh
# Compila em Release e instala o Notchkse em /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Notchkse.xcodeproj -scheme Notchkse -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build | grep -E "error:|BUILD" || true
APP=build/Build/Products/Release/Notchkse.app
# Com certificado fixo, as permissões do macOS sobrevivem aos builds.
if security find-identity -p codesigning | grep -q "Notchkse Local Signing"; then
  codesign --force --deep --options runtime --entitlements Notchkse/Notchkse.entitlements \
    -s "Notchkse Local Signing" "$APP" && echo "Assinado com Notchkse Local Signing"
else
  echo "Aviso: sem certificado fixo; permissões serão pedidas de novo (rode scripts/setup-signing.sh)"
fi
pkill -x Notchkse 2>/dev/null || true
rm -rf /Applications/Notchkse.app
cp -R "$APP" /Applications/
open /Applications/Notchkse.app
echo "Notchkse instalado em /Applications"
