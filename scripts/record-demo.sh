#!/usr/bin/env bash
# Demo screencast → optimized GIF üretim pipeline'ı.
#
# Kullanım:
#   1. macOS Screen Recording başlat (Cmd+Shift+5 → "Bir Bölümü Kaydet")
#      Ekranda PixelAgent.app penceresini seç. Sessiz; mikrofon kapalı.
#      ~20-30 saniye kayıt yap. Demo akışı (öneri):
#        a. Backend picker → Claude seç
#        b. "Merhaba" yaz, Gönder → streaming cevap gör
#        c. Plan toggle → "Plan modu — sadece okuma/araştırma" placeholder
#        d. QR butonuna tıkla → PairingView aç → kapat
#      Kayıt bitince Cmd+Shift+5 → "Durdur".
#
#   2. Çıkan .mov'u bu script'e ver:
#      scripts/record-demo.sh ~/Movies/Screen\ Recording\ ....mov
#
#   3. Script otomatik:
#      - 800px max width'e küçültür
#      - 12 fps GIF üretir (~3 MB hedef)
#      - docs/assets/demo.gif'e koyar
#
# Bağımlılık: ffmpeg (brew install ffmpeg)
# Opsiyonel: gifski (brew install gifski) — daha küçük + temiz GIF; varsa kullanır.

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <input.mov>"
    exit 1
fi

INPUT="$1"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
OUTPUT="${REPO_ROOT}/docs/assets/demo.gif"
TMP_PALETTE="$(mktemp -t pixel-palette).png"

if [ ! -f "${INPUT}" ]; then
    echo "✗ Dosya yok: ${INPUT}"
    exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

echo "→ Input: ${INPUT}"
echo "→ Output: ${OUTPUT}"

# Hedef: 800px max width, 12 fps
# gifski varsa daha iyi sonuç verir
if command -v gifski >/dev/null 2>&1; then
    echo "→ gifski tespit edildi"
    TMP_FRAMES="$(mktemp -d -t pixel-frames)"
    ffmpeg -y -i "${INPUT}" -vf "fps=12,scale=800:-1:flags=lanczos" "${TMP_FRAMES}/frame-%04d.png" 2>/dev/null
    gifski --fps 12 --width 800 --quality 90 -o "${OUTPUT}" "${TMP_FRAMES}"/frame-*.png
    rm -rf "${TMP_FRAMES}"
else
    echo "→ ffmpeg palette-based (gifski için: brew install gifski)"
    # Palette gen + apply iki geçişli yaklaşım, en iyi kalite ffmpeg-only
    ffmpeg -y -i "${INPUT}" -vf "fps=12,scale=800:-1:flags=lanczos,palettegen=stats_mode=diff" "${TMP_PALETTE}" 2>/dev/null
    ffmpeg -y -i "${INPUT}" -i "${TMP_PALETTE}" -lavfi "fps=12,scale=800:-1:flags=lanczos [v]; [v][1:v] paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" "${OUTPUT}" 2>/dev/null
    rm -f "${TMP_PALETTE}"
fi

SIZE_KB=$(du -k "${OUTPUT}" | cut -f1)
echo ""
echo "✓ ${OUTPUT} (${SIZE_KB} KB)"
if [ "${SIZE_KB}" -gt 5000 ]; then
    echo "⚠ 5 MB üstü. README için biraz büyük; ffmpeg fps/width düşürmek için scripti edit edebilirsin."
fi
