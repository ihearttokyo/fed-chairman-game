#!/usr/bin/env python3
"""Check native binary64 golden bytes using an independent rational oracle."""
import json
import struct
from fractions import Fraction
from pathlib import Path

source = (Path(__file__).resolve().parents[2] / 'game/tests/priced_stock_rounding_test.gd').read_text()
rows = json.loads(source.split('const GOLDEN_BITS := ', 1)[1].split('\nvar checks', 1)[0])
if len(rows) != 24:
    raise SystemExit('FAIL: expected 24 independent stock-rounding goldens')
for i, row in enumerate(rows):
    value, flow, closing, residual = [struct.unpack('<d', bytes.fromhex(v))[0] for v in row]
    exact_error = Fraction.from_float(closing) - Fraction.from_float(value) - Fraction.from_float(flow)
    if closing != value + flow or Fraction.from_float(residual) != exact_error:
        raise SystemExit(f'FAIL: binary64 rational golden {i}')
print(f'PASS: {len(rows)} native stock goldens verified with exact rational arithmetic')
