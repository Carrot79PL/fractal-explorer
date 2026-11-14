#!/bin/zsh
# Buduje Mandelbrot.app (bez Xcode): shader -> metallib, Swift -> binarka, podpis lokalny.
set -e
cd "$(dirname "$0")"
APP="$PWD/Mandelbrot.app"
pkill -x Mandelbrot 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
TMP=$(mktemp -d)
xcrun -sdk macosx metal -c Shaders.metal -o "$TMP/s.air"
xcrun -sdk macosx metallib "$TMP/s.air" -o "$APP/Contents/Resources/default.metallib"
[ -f AppIcon.icns ] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library *.swift -o "$APP/Contents/MacOS/Mandelbrot"
cat > "$APP/Contents/Info.plist" <<'E'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Mandelbrot</string>
<key>CFBundleIdentifier</key><string>local.mandelbrot.metal</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Mandelbrot</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHumanReadableCopyright</key><string>Autor: Tomasz Marchewka</string>
<key>CFBundleShortVersionString</key><string>1.1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
E
codesign --force --sign - "$APP" 2>&1 | grep -v "replacing" || true
echo "OK: $APP"
