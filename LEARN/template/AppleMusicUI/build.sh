#!/bin/bash
# Build script untuk AppleMusicUI template app

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR"
OUTPUT_APP="$SCRIPT_DIR/AppleMusicUI.app"
BINARY_DIR="$OUTPUT_APP/Contents/MacOS"
RESOURCES_DIR="$OUTPUT_APP/Contents/Resources"
TEMP_FILE="$SCRIPT_DIR/temp_combined.swift"

echo "🎵 Building AppleMusicUI Learning App..."

# Bersihkan build lama
rm -rf "$OUTPUT_APP"
mkdir -p "$BINARY_DIR" "$RESOURCES_DIR"

# Gabungkan semua file swift (kecuali main.swift agar @main hanya ada 1)
# Urutkan: main dulu, lalu sisanya
echo "🔨 Menggabungkan Swift files..."
cat "$SRC_DIR/main.swift" \
    "$SRC_DIR/ContentView.swift" \
    "$SRC_DIR/HomeView.swift" \
    "$SRC_DIR/SearchView.swift" \
    "$SRC_DIR/PlayerBarView.swift" \
    "$SRC_DIR/OtherViews.swift" \
    > "$TEMP_FILE"

# Kompilasi
echo "⚙️  Mengkompilasi..."
swiftc \
    -sdk $(xcrun --show-sdk-path) \
    -target arm64-apple-macos13.0 \
    -parse-as-library \
    -O \
    -o "$BINARY_DIR/AppleMusicUI" \
    "$TEMP_FILE"

RESULT=$?
rm -f "$TEMP_FILE"

if [ $RESULT -ne 0 ]; then
    echo "❌ Kompilasi gagal!"
    exit 1
fi

# Info.plist
cat > "$OUTPUT_APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AppleMusicUI</string>
    <key>CFBundleIdentifier</key>
    <string>com.learn.AppleMusicUI</string>
    <key>CFBundleName</key>
    <string>AppleMusicUI</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

# Code sign (ad-hoc)
echo "🔏 Code signing..."
codesign --force --deep --sign - "$OUTPUT_APP"

# Kill instance lama jika ada
pkill -x "AppleMusicUI" 2>/dev/null || true
sleep 0.5

# Buka app
echo "🚀 Membuka AppleMusicUI.app..."
open "$OUTPUT_APP"

echo ""
echo "✅ Selesai! App ada di:"
echo "👉 $OUTPUT_APP"
