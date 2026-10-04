#!/usr/bin/env python3
"""Validate the plain-text metadata against Apple's published field limits."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIMITS = {
    'name': (30, 'characters'),
    'subtitle': (30, 'characters'),
    'keywords': (100, 'bytes'),
    'promo': (170, 'characters'),
    'description': (4000, 'characters'),
    'reviewnotes': (4000, 'bytes'),
    'versionnotes': (4000, 'characters'),
}
errors = []
for locale in ('en', 'ru', 'uk'):
    for field, (limit, unit) in LIMITS.items():
        path = ROOT / locale / f'{field}.txt'
        if not path.is_file():
            errors.append(f'Missing {locale}/{path.name}')
            continue
        raw = path.read_text(encoding='utf-8')
        text = raw.removesuffix('\n')
        size = len(text.encode('utf-8')) if unit == 'bytes' else len(text)
        if not text or size > limit:
            errors.append(f'{locale}/{field}: {size}/{limit} {unit}')
        if field == 'name' and len(text) < 2:
            errors.append(f'{locale}/name: must contain at least two characters')
        if field in ('name', 'subtitle', 'keywords', 'promo') and '\n' in text:
            errors.append(f'{locale}/{field}: expected one line')
        if field == 'keywords' and any(len(word.strip()) <= 2 for word in text.split(',')):
            errors.append(f'{locale}/keywords: each keyword must exceed two characters')
        print(f'{locale}/{field}: {size}/{limit} {unit}')
if errors:
    raise SystemExit('\n'.join(errors))
print('All 21 metadata files fit the published limits.')
