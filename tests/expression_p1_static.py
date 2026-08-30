#!/usr/bin/env python3
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'src/waifucad/kernel/expressions.d').read_text()
for token in ['WC_EXPRESSION_DOMAIN','parseFunction','"sin".ptr','"cos".ptr','"tan".ptr','"atan2".ptr','"sqrt".ptr','"clamp".ptr','"TAU".ptr','"E".ptr']:
    assert token in s, token
assert 'Unit.degree' in s
print('Expression P1 static validation passed.')

