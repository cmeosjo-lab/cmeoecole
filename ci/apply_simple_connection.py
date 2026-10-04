"""Validate committed sources and keep native HTTP checks outside widget mocks."""
from pathlib import Path
import subprocess
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
assert 'resetDashboardCounters' in Path('lib/services/local_store.dart').read_text()
# Flutter widget tests replace HttpClient with an unconditional HTTP 400 mock.
# The loopback protocol test deliberately uses real HTTP, in a separate test
# isolate without TestWidgetsFlutterBinding. No application code is changed.
p = Path('test/simple_connection_test.dart')
s = p.read_text()
marker = "  test(\n    'pairing waits for admin and distinguishes refusal without authorizing',"
if marker in s:
    start = s.index(marker)
    end = s.index("  testWidgets('QR entry", start)
    block = s[start:end]
    target = Path('test/pairing_network_test.dart')
    if target.exists():
        raise RuntimeError('Refuse to overwrite an existing protocol test')
    target.write_text("import 'dart:convert';\nimport 'dart:io';\nimport 'package:flutter_test/flutter_test.dart';\nimport 'package:ecole_gestion_prof_mobile/services/principal_api.dart';\n\nvoid main() {\n" + block + "}\n")
    p.write_text(s[:start] + s[end:])
subprocess.run(['flutter','pub','get','--enforce-lockfile'],check=True)
subprocess.run(['dart','fix','--apply','lib'],check=True)
print('V0.6.2 : données, schéma et dépendances inchangés ; tests HTTP et widgets isolés.')
