#!/usr/bin/env python3
"""Isolated CLI regressions. Never touches the user's bucket or original files."""
import concurrent.futures
import os
from pathlib import Path
import subprocess
import tempfile
import unicodedata

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='bucket-regression-') as temp:
    root = Path(temp).resolve()
    env = {**os.environ, 'BUCKET_HOME': str(root / 'state')}
    def cli(*args, ok=True):
        p = subprocess.run([str(ROOT / 'bucket'), *map(str, args)], env=env, capture_output=True, text=True)
        assert (p.returncode == 0) == ok, (args, p.returncode, p.stderr)
        # Foundation and Python spell /private/var and decomposed Unicode differently on macOS.
        return [unicodedata.normalize('NFC', str(Path(line).resolve())) for line in p.stdout.splitlines()]
    first = root / 'spaces ü # %.txt'
    first.write_bytes(bytes(range(256)))
    empty = root / 'empty.txt'
    empty.write_bytes(b'')
    link = root / 'alias.txt'
    link.symlink_to(first)
    cli('add', first, empty, first, link)
    assert cli('list') == [str(first), str(empty)], (cli('list'), [str(first), str(empty)])
    extra = root / 'extra.txt'
    extra.write_bytes(b'preserve me')
    cli('add', extra, root / 'missing', ok=False)
    cli('add', root, ok=False)
    cli('add', ok=False)
    cli('bogus', ok=False)
    assert cli('list') == [str(first), str(empty)], 'invalid batch was not atomic'
    assert (root / 'state').stat().st_mode & 0o777 == 0o700
    assert (root / 'state/manifest.json').stat().st_mode & 0o777 == 0o600
    cli('clear')
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        list(pool.map(lambda _: cli('add', first, empty, extra), range(24)))
    assert set(cli('list')) == {str(first), str(empty), str(extra)}
    assert len(cli('list')) == 3
    empty.unlink()
    cli('add', empty, ok=False)
    assert len(cli('list')) == 3, 'missing source must not silently rewrite manifest'
    cli('clear')
    assert cli('list') == []
    assert first.read_bytes() == bytes(range(256))
    assert extra.read_bytes() == b'preserve me'
    assert link.is_symlink()
print('PASS: CLI unicode/spaces, empty files, symlink dedup, batch atomicity, invalid inputs, permissions, 24 concurrent adds, missing source, clear and preservation')
