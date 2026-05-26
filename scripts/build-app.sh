#!/usr/bin/env bash
# Mac için PixelAgent.app bundle üret.
#
# Kullanım:
#   scripts/build-app.sh [debug|release]   # default: release
#   open PixelAgent.app                     # bundle'ı çalıştır
#
# .app bundle çalıştırıldığında UNUserNotificationCenter, dock badge gibi
# bundle-gerektiren API'ler doğru çalışır (swift run binary doğrudan
# çalıştırıldığında çalışmaz).

set -euo pipefail

CONFIG="${1:-release}"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

APP_NAME="PixelAgent"
APP_BUNDLE="${APP_NAME}.app"
EXECUTABLE_NAME="${APP_NAME}"
BUNDLE_ID="dev.erkutyavuzer.pixel-agent"
VERSION="0.2.61"
BUILD="61"

echo "→ swift build -c ${CONFIG}"
swift build -c "${CONFIG}"

MAC_BINARY=".build/arm64-apple-macosx/${CONFIG}/PixelMacApp"
MCP_BINARY=".build/arm64-apple-macosx/${CONFIG}/pixel-mcp-server"
for bin in "${MAC_BINARY}" "${MCP_BINARY}"; do
    if [ ! -f "$bin" ]; then
        echo "✗ Binary bulunamadı: $bin"
        exit 1
    fi
done

echo "→ ${APP_BUNDLE} bundle hazırlanıyor (PixelMacApp + pixel-mcp-server)"
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${MAC_BINARY}" "${APP_BUNDLE}/Contents/MacOS/${EXECUTABLE_NAME}"
# pixel-mcp-server bundle içinde — AboutView'daki "MCP Entegrasyonu" sheet'i bu
# path'i otomatik bulur ve IDE'lere config snippet'i üretir.
cp "${MCP_BINARY}" "${APP_BUNDLE}/Contents/MacOS/pixel-mcp-server"
chmod +x "${APP_BUNDLE}/Contents/MacOS/pixel-mcp-server"

cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>pixel-agent</string>
    <key>CFBundleDisplayName</key>
    <string>pixel-agent</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>iPhone'unuzla doğrudan LAN üzerinden (Bonjour) eşleşmek için.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_pixel-agent._tcp</string>
    </array>
</dict>
</plist>
EOF

echo "→ codesign (ad-hoc)"
codesign --force --sign - "${APP_BUNDLE}" 2>&1 | sed 's/^/  /'

echo ""
echo "✓ ${APP_BUNDLE} hazır."
echo "  Çalıştırmak için: open ${APP_BUNDLE}"
