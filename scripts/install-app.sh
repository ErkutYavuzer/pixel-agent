#!/usr/bin/env bash
# PixelAgent.app'i /Applications/ klasörüne kopyalar — macOS Launchpad
# otomatik tanır. Önce scripts/build-app.sh ile bundle üretilir.
#
# Kullanım:
#   scripts/install-app.sh
#   open -a pixel-agent     # her yerden başlat

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

APP_BUNDLE="PixelAgent.app"
INSTALL_DIR="/Applications"
INSTALLED_PATH="${INSTALL_DIR}/${APP_BUNDLE}"

# Bundle henüz yoksa veya binary eskidiyse build et
if [ ! -d "${APP_BUNDLE}" ] || [ ".build/arm64-apple-macosx/release/PixelMacApp" -nt "${APP_BUNDLE}/Contents/MacOS/PixelAgent" ]; then
    echo "→ Bundle güncel değil, yeniden build ediyorum"
    "${REPO_ROOT}/scripts/build-app.sh" release
fi

echo "→ Çalışan instance varsa kapat"
pkill -f "${APP_BUNDLE}" 2>/dev/null || true
sleep 1

echo "→ Eski kurulumu kaldır"
if [ -d "${INSTALLED_PATH}" ]; then
    rm -rf "${INSTALLED_PATH}"
fi

echo "→ ${APP_BUNDLE} → ${INSTALLED_PATH}"
cp -R "${APP_BUNDLE}" "${INSTALLED_PATH}"

echo ""
echo "✓ Kurulum tamam."
echo "  Launchpad'de 'pixel-agent' ara veya:"
echo "  open -a pixel-agent"
