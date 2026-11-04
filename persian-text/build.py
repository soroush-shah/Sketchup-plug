#!/usr/bin/env python3
"""Packages src/ into dist/bs_persian_text_v<version>.rbz (an .rbz is a zip)."""
import os, re, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src')
loader = open(os.path.join(SRC, 'bs_persian_text.rb'), encoding='utf-8').read()
version = re.search(r"PLUGIN_VERSION = '([^']+)'", loader).group(1)
os.makedirs(os.path.join(HERE, 'dist'), exist_ok=True)
out = os.path.join(HERE, 'dist', 'bs_persian_text_v%s.rbz' % version)

with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _dirs, files in os.walk(SRC):
        for name in sorted(files):
            path = os.path.join(root, name)
            z.write(path, os.path.relpath(path, SRC).replace(os.sep, '/'))
print(out)
