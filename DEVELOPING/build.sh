#!/bin/bash
set -e

# Dapatkan path direktori DEVELOPING
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="ShortKing"
APP_BUNDLE="$DIR/bin/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Membersihkan build lama..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "🔨 Mengkompilasi Swift Macro Engine..."
swiftc "$DIR/src/main.swift" -o "$MACOS_DIR/$APP_NAME" -O

echo "📝 Membuat Info.plist untuk $APP_NAME.app..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.redmunky.shortking</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>ShortKing Macro Script</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>shortking</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.redmunky.shortking.script</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.redmunky.shortking.script</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.content</string>
            </array>
            <key>UTTypeDescription</key>
            <string>ShortKing Macro Script</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>shortking</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "🔏 Menandatangani App Bundle (Ad-hoc Code Signing)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🔄 Menghentikan aplikasi yang sedang berjalan (jika ada)..."
killall "$APP_NAME" 2>/dev/null || true

echo "🚀 Menjalankan ulang aplikasi $APP_NAME.app..."
open "$APP_BUNDLE"

echo "✅ Sukses! Aplikasi native macOS siap di:"
echo "👉 $APP_BUNDLE"
