# -*- coding: utf-8 -*-
"""Quality gate for app_zh.arb.

Checks: key parity, placeholder parity, ICU plural branch parity,
Chinese coverage, brand leakage and preservation of proper nouns.
"""
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ROOT = os.path.join(REPO, 'lib', 'l10n')
EN = os.path.join(ROOT, 'app_en.arb')
ZH = os.path.join(ROOT, 'app_zh.arb')

# Product / protocol / technical names that must keep their original spelling.
KEEP = [
    'Emby', 'Jellyfin', 'TMDB', 'MDBList', 'Seerr', 'Xtream', 'IPTV',
    'Discord', 'Home Assistant', 'mpv', 'Dolby', 'TrueHD', 'DTS-HD',
    'WASAPI', 'D3D11', 'NVDEC', 'NVIDIA', 'gpu-next', 'ASS', 'M3U',
    'XMLTV', 'Tunarr', 'NostalgiaTV', 'YouTube', 'HDR', 'HLG', 'HDR10',
    'SDR', 'Windows', 'HDMI', 'API', 'Hz', 'CPU', 'DVD', 'JSON', 'Top 10',
]

# Terms with an established Chinese name (intentionally translated).
LOCALISED = [
    'LaLiga', 'Premier League', 'UEFA', 'Rotten Tomatoes', 'Blu-ray',
    'Notepad', 'VHS', 'AV receiver', 'soundbar', 'GPU', 'QR code',
]

# ARB placeholder names are ASCII identifiers only; \w would also match
# Chinese ICU branch bodies like "=0{未选择}".
PLACEHOLDER = re.compile(r'\{([A-Za-z_][A-Za-z0-9_]*)\}')
BRANCH = re.compile(r'(=\d+|other)\{')
HAN = re.compile(r'[\u4e00-\u9fff]')

# Values that are correct without Chinese characters (brands / proper nouns).
NO_HAN_OK = {
    'codeEyebrow', 'metadataSourceTmdb', 'hwdecNvdec', 'videoRendererNext',
    'appVersionLabel', 'hubLinkedSettingValue', 'seerrAddressHint',
    'calendarDay', 'calendarMonth', 'calendarMore',
}

# Upstream-specific calls to action this fork deliberately removes. Each entry
# is an explicit, auditable exception: only the listed proper noun may be
# absent from the listed key. Everything else still fails the gate.
INTENTIONAL_DROPS = {
    'sendLogsHint': {
        'Discord': 'logs go to the self-hosted service, not the upstream Discord',
    },
    'sendLogsDoneBody': {
        'Discord': 'this fork has no official Discord channel',
    },
}

en = json.load(open(EN, encoding='utf-8'))
zh = json.load(open(ZH, encoding='utf-8'))
en_keys = [k for k in en if not k.startswith('@')]
zh_keys = [k for k in zh if not k.startswith('@')]

errors = []
warnings = []

if set(en_keys) != set(zh_keys):
    errors.append(f'key mismatch: missing={sorted(set(en_keys) - set(zh_keys))} '
                  f'extra={sorted(set(zh_keys) - set(en_keys))}')
if zh.get('@@locale') != 'zh':
    errors.append(f"@@locale is {zh.get('@@locale')!r}, expected 'zh'")

identical = []
for k in en_keys:
    e, z = str(en[k]), str(zh[k])
    if set(PLACEHOLDER.findall(e)) != set(PLACEHOLDER.findall(z)):
        errors.append(f'placeholder mismatch: {k} | {e} => {z}')
    if 'plural' in e or 'select' in e:
        be, bz = set(BRANCH.findall(e)), set(BRANCH.findall(z))
        if be != bz:
            errors.append(f'ICU branch mismatch: {k} | {sorted(be)} => {sorted(bz)}')
    for word in KEEP:
        if word in e and word not in z:
            if word in INTENTIONAL_DROPS.get(k, {}):
                continue
            errors.append(f'proper noun lost: {k} | {word} missing in "{z}"')
    if 'Zerk' in z or 'zerkplay' in z:
        errors.append(f'upstream brand leaked: {k} => {z}')
    if e == z:
        identical.append(k)
    elif not HAN.search(z) and k not in NO_HAN_OK:
        warnings.append(f'no Chinese characters: {k} => {z}')

localised_coverage = sum(1 for k in en_keys if str(en[k]) != str(zh[k]))
print(f'keys: en={len(en_keys)} zh={len(zh_keys)}')
print(f'localised values: {localised_coverage}/{len(en_keys)} '
      f'({localised_coverage * 100 // len(en_keys)}%)')
print(f'unchanged (symbol-only) keys: {len(identical)} -> {identical}')
print(f'KEEP whitelist: {len(KEEP)} | LOCALISED exceptions: {len(LOCALISED)} '
      f'| intentional drops: {sum(len(v) for v in INTENTIONAL_DROPS.values())}')
for k, drops in INTENTIONAL_DROPS.items():
    for word, reason in drops.items():
        print(f'  DROP {k}: {word} ({reason})')
print(f'warnings: {len(warnings)}')
for w in warnings:
    print('  WARN', w)
print(f'errors: {len(errors)}')
for e in errors:
    print('  ERROR', e)
print('RESULT:', 'PASS' if not errors else 'FAIL')
sys.exit(1 if errors else 0)
