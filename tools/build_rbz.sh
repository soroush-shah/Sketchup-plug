#!/usr/bin/env bash
# Builds dist/skpshare-<version>.rbz (SketchUp extension package).
# Downloads the official gltfpack binaries (MIT licence, github.com/zeux/meshoptimizer) for Windows and macOS
# so models are compressed on the designer's computer before upload.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep -o "VERSION = '[^']*'" "$ROOT/plugin/skpshare.rb" | cut -d"'" -f2)"
GLTFPACK_TAG="${GLTFPACK_TAG:-latest}"
BIN="$ROOT/plugin/skpshare/bin"
mkdir -p "$BIN/win" "$BIN/mac" "$ROOT/dist"

fetch() { # $1 asset  $2 dest dir  $3 binary name
  local url
  if [ "$GLTFPACK_TAG" = latest ]; then url="https://github.com/zeux/meshoptimizer/releases/latest/download/$1"
  else url="https://github.com/zeux/meshoptimizer/releases/download/$GLTFPACK_TAG/$1"; fi
  if [ -f "$2/$3" ]; then echo "✔ $2/$3 already present"; return; fi
  echo "↓ $url"
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/a.zip"; then
    python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$tmp/a.zip" "$tmp/x"
    find "$tmp/x" -name "$3" -type f -exec cp {} "$2/$3" \;
    chmod +x "$2/$3" || true
    echo "✔ $2/$3"
  else
    echo "⚠ could not download $1 – the plugin will upload uncompressed GLB on that platform"
  fi
  rm -rf "$tmp"
}

fetch gltfpack-windows.zip "$BIN/win" gltfpack.exe
fetch gltfpack-macos.zip "$BIN/mac" gltfpack

OUT="$ROOT/dist/skpshare-$VERSION.rbz"
rm -f "$OUT"
python3 - "$ROOT/plugin" "$OUT" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src, 'skpshare.rb'), 'skpshare.rb')
    for base, _, files in os.walk(os.path.join(src, 'skpshare')):
        for f in files:
            p = os.path.join(base, f)
            info = zipfile.ZipInfo.from_file(p, os.path.relpath(p, src))
            if f == 'gltfpack':
                info.external_attr = 0o755 << 16
            with open(p, 'rb') as fh:
                z.writestr(info, fh.read(), zipfile.ZIP_DEFLATED)
print('built', out, os.path.getsize(out), 'bytes')
PY
