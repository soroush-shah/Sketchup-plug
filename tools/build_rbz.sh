#!/usr/bin/env bash
# Builds dist/banian_floor_studio_v<version>.rbz from src/
set -euo pipefail
cd "$(dirname "$0")/.."
VER=$(ruby -e 'print File.read("src/banian_floor_studio.rb")[/VERSION = .(\d+\.\d+\.\d+)/, 1]')
mkdir -p dist
OUT="dist/banian_floor_studio_v${VER}.rbz"
rm -f "$OUT"
(cd src && zip -qr -X "../$OUT" banian_floor_studio.rb banian_floor_studio -x '*.DS_Store')
echo "built $OUT"
unzip -l "$OUT" | tail -1
