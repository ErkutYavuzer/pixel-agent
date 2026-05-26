#!/usr/bin/env bash
# Cloudflare Worker relay'ini production'a deploy et.
#
# Kullanım:
#   scripts/deploy-relay.sh
#
# Önkoşul:
#   - Cloudflare hesabı + workers.dev subdomain
#   - `npx wrangler login` ile auth (ilk kez)
#
# Sonuç: Deploy başarılı olursa wrangler URL'i bastırır
#   (https://pixel-agent-relay.<subdomain>.workers.dev). Bu URL'i kullanıcı
#   PixelAgent Settings → Bağlantı → "Özel URL" alanına yapıştırır (wss://
#   prefix ile) — Sprint 47 RelayURLResolver custom override path'i.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RELAY_DIR="${REPO_ROOT}/relay"

if [ ! -d "${RELAY_DIR}" ]; then
    echo "✗ ${RELAY_DIR} dizini yok. Repo root'tan çağırın."
    exit 1
fi

cd "${RELAY_DIR}"

# Wrangler kurulu mu kontrol
if ! command -v npx >/dev/null; then
    echo "✗ npx bulunamadı. `brew install node` ile Node.js kurun."
    exit 1
fi

# Auth check (whoami → 0 ise login, ≠0 ise login gerek)
echo "→ Cloudflare auth check..."
if ! npx wrangler whoami 2>&1 | grep -q "You are logged in"; then
    echo "→ Login gerek. Browser'da Cloudflare authorize ekranı açılacak..."
    npx wrangler login
fi

# Deploy
echo "→ Deploy başlatılıyor..."
npx wrangler deploy

cat <<'EOF'

✓ Deploy tamamlandı.

Sonraki adım — kullanıcı Mac app'inde:
  1. PixelAgent → Settings (⌘,) → "Bağlantı" tab
  2. "Özel URL" alanına yukarıdaki wrangler URL'ini wss:// prefix ile yapıştır:
     wss://pixel-agent-relay.<subdomain>.workers.dev
  3. "Wrangler'ı Otomatik Başlat" toggle kapatılabilir (production URL var artık)
  4. App restart → production relay aktif

Lokal wrangler subprocess artık gereksiz; iOS de her zaman aynı public URL'e bağlanır.
EOF
