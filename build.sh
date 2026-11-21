#!/bin/bash
# Build the game directly from ARM64 assembly. SDL is only the platform layer.
set -euo pipefail
cd "$(dirname "$0")"
SDL2_PREFIX="${SDL2_PREFIX:-/opt/homebrew/opt/sdl2}"
SDL3_PREFIX="${SDL3_PREFIX:-/opt/homebrew/opt/sdl3}"
APP="Tidebloom-Journeys.app"
BIN="$APP/Contents/MacOS/tidebloom"
FRAMEWORKS="$APP/Contents/Frameworks"
mkdir -p "$APP/Contents/MacOS" "$FRAMEWORKS" "$APP/Contents/Resources" third-party
if [ ! -f "$SDL2_PREFIX/lib/libSDL2.dylib" ]; then
  echo "SDL2 is required to rebuild. Install with: brew install sdl2"
  exit 1
fi
clang -arch arm64 -mmacosx-version-min=27.0 -O2 \
  src/main.s src/game.s src/world.s src/save.s src/recorder.s src/anim.s src/audio.s src/effects.s src/render.s src/assets.s \
  -L"$SDL2_PREFIX/lib" -lSDL2 -framework Cocoa \
  -Wl,-rpath,@executable_path/../Frameworks -o "$BIN"
cp -L "$SDL2_PREFIX/lib/libSDL2.dylib" "$FRAMEWORKS/libSDL2.dylib"
chmod u+w "$FRAMEWORKS/libSDL2.dylib"
SDL2_ID="$(otool -L "$BIN" | awk '/libSDL2.*dylib/ {print $1; exit}')"
install_name_tool -change "$SDL2_ID" '@rpath/libSDL2.dylib' "$BIN"
install_name_tool -id '@rpath/libSDL2.dylib' "$FRAMEWORKS/libSDL2.dylib"
cp "$SDL2_PREFIX/LICENSE.txt" third-party/SDL2-LICENSE.txt
# Homebrew's sdl2-compat finds SDL3 next to itself through @loader_path.
if [ -f "$SDL3_PREFIX/lib/libSDL3.dylib" ]; then
  cp -L "$SDL3_PREFIX/lib/libSDL3.dylib" "$FRAMEWORKS/libSDL3.dylib"
  chmod u+w "$FRAMEWORKS/libSDL3.dylib"
  install_name_tool -id '@rpath/libSDL3.dylib' "$FRAMEWORKS/libSDL3.dylib"
  cp "$SDL3_PREFIX/LICENSE.txt" third-party/SDL3-LICENSE.txt
  codesign --force --sign - "$FRAMEWORKS/libSDL3.dylib"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>tidebloom</string>
<key>CFBundleIdentifier</key><string>games.tidebloom.journeys</string>
<key>CFBundleName</key><string>Tidebloom Journeys</string>
<key>CFBundleDisplayName</key><string>Tidebloom Journeys</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>27.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
cp third-party/*LICENSE.txt "$APP/Contents/Resources/"
codesign --force --sign - "$FRAMEWORKS/libSDL2.dylib"
codesign --force --sign - "$BIN"
codesign --force --deep --sign - "$APP"
printf '\nBuilt %s/%s\n' "$PWD" "$APP"
printf 'Run: open Tidebloom-Journeys.app\nTest: Tidebloom-Journeys.app/Contents/MacOS/tidebloom --self-test\n'
