"""Validate committed V0.6.2; retain production storage and fix test-only HTTP override."""
from pathlib import Path
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
p = Path('test/followup_connection_test.dart')
s = p.read_text().replace('final previousOverrides = HttpOverrides.global;', 'final previousOverrides = HttpOverrides.current;')
p.write_text(s)
