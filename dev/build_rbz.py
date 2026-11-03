#!/usr/bin/env python3
"""Packs src/ into dist/banian_browser_v<version>.rbz (an .rbz is a zip)."""
import os, re, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'src')
version = re.search(r"VERSION = '([^']+)'", open(os.path.join(SRC, 'banian_browser.rb'), encoding='utf-8').read()).group(1)
os.makedirs(os.path.join(ROOT, 'dist'), exist_ok=True)
out = os.path.join(ROOT, 'dist', f'banian_browser_v{version}.rbz')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for base, _dirs, files in os.walk(SRC):
        for f in sorted(files):
            if f.startswith('.') or f.endswith('.svg') and 'cursor_' in f:
                continue
            full = os.path.join(base, f)
            z.write(full, os.path.relpath(full, SRC).replace(os.sep, '/'))
print(out, os.path.getsize(out), 'bytes')
