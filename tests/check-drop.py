#!/usr/bin/env python3
"""Fail unless a real native receiver read exactly the expected fixture bytes."""
import base64
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
report = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'build/drag-state/drop-test.json'
names = sys.argv[2:] or ['Hello bucket.txt']
if not report.exists():
    sys.exit('FAIL: no native drop report. Drag is NOT verified.')
received = json.loads(report.read_text())
expected = [root / 'fixtures' / name for name in names]
assert len(received) == len(expected), 'wrong file count'
for item, path in zip(received, expected):
    data = path.read_bytes()
    assert item['name'] == path.name, 'wrong filename'
    assert item['size'] == len(data), 'wrong size'
    assert base64.b64decode(item['base64'], validate=True) == data, 'wrong bytes'
print('PASS: native drop received exact filenames and bytes:', ', '.join(names))
