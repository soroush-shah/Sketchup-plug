#!/usr/bin/env bash
# Builds everything and produces two files in dist/:
#   skpshare-server.zip  – upload to your host and extract inside public_html
#   skpshare-<v>.rbz     – SketchUp extension (also published at /downloads/skpshare.rbz on the site)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== web app"
(cd web && npm ci --no-audit --no-fund && npm run build)

echo "== SketchUp plugin"
tools/build_rbz.sh
RBZ="$(ls -t dist/skpshare-*.rbz | head -1)"
mkdir -p server/public/downloads
cp "$RBZ" server/public/downloads/skpshare.rbz

echo "== server package (shared hosting layout: everything in public_html, app code in _app/)"
STAGE="$(mktemp -d)"
cp -R server/public/. "$STAGE/"
mkdir -p "$STAGE/_app"
cp -R server/src server/migrations server/config.sample.php "$STAGE/_app/"
mkdir -p "$STAGE/_app/storage"
cp server/storage/.htaccess "$STAGE/_app/storage/"
printf 'Require all denied\nDeny from all\n' > "$STAGE/_app/.htaccess"
rm -f "$STAGE/_app/config.php"
OUT="$ROOT/dist/skpshare-server.zip"
rm -f "$OUT"
python3 - "$STAGE" "$OUT" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, src))
print('built', out, os.path.getsize(out) // 1024, 'KB')
PY
rm -rf "$STAGE"
echo "Done. Upload dist/skpshare-server.zip to public_html, extract, then open https://your-site/install.php"
