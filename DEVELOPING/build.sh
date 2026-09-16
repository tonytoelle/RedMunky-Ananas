#!/bin/bash
set -e
BUILD_START=$(date +%s)

# Dapatkan path direktori DEVELOPING
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="RedMunky Ananas"

# Mode: --release untuk optimasi penuh (public build), default = dev (cepat)
if [[ "$1" == "--release" ]]; then
    SWIFT_OPT="-O"
    echo "🚀 MODE: RELEASE (optimasi penuh untuk publik)"
else
    SWIFT_OPT="-Onone"
    echo "⚡ MODE: DEV (kompilasi super cepat)"
fi
APP_BUNDLE="$DIR/bin/$APP_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

echo "🔨 Membersihkan build lama..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Membangun AppIcon.icns
cat << 'EOF' > "$DIR/temp_generate_icns.swift"
import Cocoa

func generateAppIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    
    // 1. Solid colored squircle background (matches action card color: R: 0.32, G: 0.28, B: 0.72)
    let bgRect = NSRect(origin: .zero, size: size)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 220, yRadius: 220)
    NSColor(red: 0.32, green: 0.28, blue: 0.72, alpha: 1.0).set()
    bgPath.fill()
    
    // 2. Draw white flat SF Symbol crown.fill in the center
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: 440, weight: .bold)
    if let symbolImage = NSImage(systemSymbolName: "crown.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
        let symbolSize = symbolImage.size
        let symRect = NSRect(
            x: (size.width - symbolSize.width) / 2,
            y: (size.height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        
        // Tint symbol white
        if let tintedSym = symbolImage.copy() as? NSImage {
            tintedSym.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: tintedSym.size).fill(using: .sourceAtop)
            tintedSym.unlockFocus()
            tintedSym.draw(in: symRect)
        }
    }
    
    image.unlockFocus()
    return image
}

let image = generateAppIcon()
if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
    if let pngData = bitmap.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: "temp_icon_1024.png"))
    }
}
EOF

echo "🔨 Membangun AppIcon.icns..."
swift "$DIR/temp_generate_icns.swift"
rm -f "$DIR/temp_generate_icns.swift"

mkdir -p "$DIR/AppIcon.iconset"
sips -z 16 16     temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_16x16.png" >/dev/null 2>&1
sips -z 32 32     temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 32 32     temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_32x32.png" >/dev/null 2>&1
sips -z 64 64     temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 128 128   temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_128x128.png" >/dev/null 2>&1
sips -z 256 256   temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 256 256   temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_256x256.png" >/dev/null 2>&1
sips -z 512 512   temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 512 512   temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_512x512.png" >/dev/null 2>&1
sips -z 1024 1024 temp_icon_1024.png --out "$DIR/AppIcon.iconset/icon_512x512@2x.png" >/dev/null 2>&1

iconutil -c icns "$DIR/AppIcon.iconset" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$DIR/AppIcon.iconset"
rm -f temp_icon_1024.png

echo "🔨 Menyalin dokumen default ke dalam Resources..."
mkdir -p "$RESOURCES_DIR/DefaultDocuments"
cp -R "$DIR/../INPUT/Ananas Documents/" "$RESOURCES_DIR/DefaultDocuments/"


echo "🔨 Menggabungkan file Swift untuk kompilasi super cepat..."
TEMP_BUILD_FILE="$DIR/src/temp_build.swift"
rm -f "$TEMP_BUILD_FILE"
find "$DIR/src" -name "*.swift" ! -name "temp_build.swift" | while read -r file; do
    cat "$file"
    echo ""
done > "$TEMP_BUILD_FILE"

echo "🔨 Mengkompilasi Swift Macro Engine..."
swiftc "$TEMP_BUILD_FILE" -o "$MACOS_DIR/$APP_NAME" $SWIFT_OPT -F /System/Library/PrivateFrameworks -framework DisplayServices
rm -f "$TEMP_BUILD_FILE"

echo "📝 Membuat Info.plist untuk $APP_NAME.app..."
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.redmunky.ananas</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
            <string>RedMunky Ananas Macro Script</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>nanas</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Owner</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.redmunky.ananas.script</string>
            </array>
        </dict>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>
            <string>com.redmunky.ananas.script</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.data</string>
                <string>public.content</string>
            </array>
            <key>UTTypeDescription</key>
            <string>RedMunky Ananas Macro Script</string>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>nanas</string>
                </array>
            </dict>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "🔏 Menandatangani App Bundle (Ad-hoc Code Signing)..."
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "🔄 Menghentikan aplikasi yang sedang berjalan (jika ada)..."
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5

echo "🚀 Menjalankan ulang aplikasi $APP_NAME.app..."
open "$APP_BUNDLE"

echo "✅ Sukses! Aplikasi native macOS siap di:"
echo "👉 $APP_BUNDLE"

BUILD_END=$(date +%s)
echo "⏱️  Build selesai dalam $((BUILD_END - BUILD_START)) detik"
