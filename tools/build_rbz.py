#!/usr/bin/env python3
"""Package the extension into dist/banian_profile_builder_v<version>.rbz"""
import os, re, zipfile
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(root, 'src')
loader = os.path.join(src, 'banian_profile_builder.rb')
version = re.search(r"VERSION = '([^']+)'", open(loader, encoding='utf-8').read()).group(1)
os.makedirs(os.path.join(root, 'dist'), exist_ok=True)
out = os.path.join(root, 'dist', f'banian_profile_builder_v{version}.rbz')
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    z.write(loader, 'banian_profile_builder.rb')
    for base, _, files in os.walk(os.path.join(src, 'banian_profile_builder')):
        for f in sorted(files):
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, src).replace(os.sep, '/'))
print(out)
