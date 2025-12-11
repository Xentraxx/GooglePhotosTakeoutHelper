#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('--version', required=True, help='v5.0.2 o 5.0.2 (opcionalmente con -beta1, -rc1, etc.)')
p.add_argument('--file', default='CHANGELOG.md')
args = p.parse_args()

raw = args.version.strip().lstrip('v')

m = re.fullmatch(r'(\d+\.\d+\.\d+)(?:-([A-Za-z0-9.+-]+))?', raw)
if not m:
    raise ValueError(f'Invalid version: {args.version}')
base, suffix = m.group(1), m.group(2)

text = Path(args.file).read_text(encoding='utf-8', errors='replace')

# Si el usuario dio sufijo -> coincidencia exacta; si no -> sufijo opcional
if suffix:
    header_re = re.compile(rf'(?m)^##\s+{re.escape(base)}-{re.escape(suffix)}(?=\s|$)')
else:
    header_re = re.compile(rf'(?m)^##\s+{re.escape(base)}(?:-[A-Za-z0-9.+-]+)?(?=\s|$)')

m = header_re.search(text)
if not m:
    found = re.findall(r'(?m)^##\s+(\d+\.\d+\.\d+(?:-[A-Za-z0-9.+-]+)?)', text)
    sys.stderr.write(
        f'Version "{raw}" not found in {args.file}.\n'
        f'Available: {", ".join(found[:20])}\n'
    )
    sys.exit(1)

start = m.end()
nxt = re.search(r'(?m)^##\s+', text[start:])
end = start + nxt.start() if nxt else len(text)

print(text[start:end].strip())
