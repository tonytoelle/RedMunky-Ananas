#!/bin/bash
set -e

# Dapatkan path direktori DEVELOPING dan ROOT project
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$DIR")"
APP_NAME="ShortKing"
DMG_NAME="$APP_NAME"
OUTPUT_DIR="$ROOT_DIR/output"
TEMP_DIR="$DIR/bin/dmg_temp"

echo "📦 Memulai proses packaging untuk $APP_NAME..."

# 1. Pastikan build release terbaru dikompilasi
echo "🚀 1. Mengkompilasi build release..."
"$DIR/build.sh" --release

# 2. Bersihkan target DMG lama dan folder temp
echo "🧹 2. Membersihkan sisa build kemasan sebelumnya..."
rm -f "$OUTPUT_DIR/$DMG_NAME.dmg"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# 3. Salin ShortKing.app ke folder temporary DMG
echo "📂 3. Mempersiapkan folder kemasan..."
cp -R "$DIR/bin/$APP_NAME.app" "$TEMP_DIR/"

# 4. Buat symlink ke /Applications di dalam folder temporary DMG
echo "🔗 4. Membuat symlink ke folder /Applications..."
ln -s /Applications "$TEMP_DIR/Applications"

# 5. Buat DMG menggunakan hdiutil
echo "💾 5. Membuat berkas Disk Image (.dmg)..."
hdiutil create -volname "$APP_NAME Installer" -srcfolder "$TEMP_DIR" -ov -format UDZO "$OUTPUT_DIR/$DMG_NAME.dmg"

# 6. Bersihkan folder temporary
echo "🧹 6. Melakukan pembersihan berkas temporary..."
rm -rf "$TEMP_DIR"

echo "✅ Selesai! DMG installer siap digunakan oleh end-user di:"
echo "👉 $OUTPUT_DIR/$DMG_NAME.dmg"
