#!/bin/bash
set -euo pipefail

BUILD_START=$(date +%s)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ShortKing"
APP_BUNDLE="$DIR/bin/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
TEMP_BINARY="$MACOS_DIR/$APP_NAME.new"
BUILD_CACHE="$DIR/.build-fast"
OUTPUT_MAP="$BUILD_CACHE/output-file-map.json"
MODULE_PATH="$BUILD_CACHE/$APP_NAME.swiftmodule"

if [[ ! -d "$APP_BUNDLE" || ! -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    echo "📦 App bundle belum lengkap; menjalankan build penuh sekali..."
    exec "$DIR/build.sh"
fi

echo "⚡ FAST DEV BUILD (resource cache + multi-file compile)"
mkdir -p "$MACOS_DIR"
mkdir -p "$BUILD_CACHE"

SOURCE_FILES=()
while IFS= read -r -d '' file; do
    SOURCE_FILES+=("$file")
done < <(find "$DIR/src" -name "*.swift" ! -name "temp_build.swift" -print0)

MAP_JSON='{"":{"swiftmodule":""}}'
for file in "${SOURCE_FILES[@]}"; do
    base="$(basename "$file" .swift)"
    MAP_JSON="$(jq --arg key "$file" \
        --arg object "$BUILD_CACHE/$base.o" \
        --arg deps "$BUILD_CACHE/$base.swiftdeps" \
        --arg diagnostics "$BUILD_CACHE/$base.dia" \
        '. + {($key): {object: $object, "swift-dependencies": $deps, diagnostics: $diagnostics}}' \
        <<< "$MAP_JSON")"
done
jq --arg module "$MODULE_PATH" '.[""].swiftmodule = $module' <<< "$MAP_JSON" > "$OUTPUT_MAP"

echo "🔨 Incremental compile ${#SOURCE_FILES[@]} file Swift..."
swiftc "${SOURCE_FILES[@]}" \
    -c \
    -incremental \
    -module-name "$APP_NAME" \
    -output-file-map "$OUTPUT_MAP" \
    -emit-module \
    -emit-module-path "$MODULE_PATH" \
    -Onone \
    -F /System/Library/PrivateFrameworks \
    -framework DisplayServices

OBJECT_FILES=()
while IFS= read -r object; do
    OBJECT_FILES+=("$object")
done < <(jq -r 'to_entries[] | select(.key != "") | .value.object' "$OUTPUT_MAP")

echo "🔗 Linking binary..."
swiftc "${OBJECT_FILES[@]}" \
    -o "$TEMP_BINARY" \
    -module-name "$APP_NAME" \
    -F /System/Library/PrivateFrameworks \
    -framework DisplayServices

echo "🔄 Mengganti binary setelah compile berhasil..."
killall "$APP_NAME" 2>/dev/null || true
sleep 0.2
mv "$TEMP_BINARY" "$MACOS_DIR/$APP_NAME"

echo "🔏 Sign binary baru..."
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🚀 Menjalankan ulang aplikasi..."
open "$APP_BUNDLE"

BUILD_END=$(date +%s)
echo "✅ Fast build selesai dalam $((BUILD_END - BUILD_START)) detik"
echo "👉 $APP_BUNDLE"
