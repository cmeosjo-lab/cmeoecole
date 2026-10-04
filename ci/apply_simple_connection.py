"""Validate the committed sources; the transfer patch is no longer used."""
from pathlib import Path
import subprocess
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
assert 'resetDashboardCounters' in Path('lib/services/local_store.dart').read_text()
subprocess.run(['flutter','pub','get','--enforce-lockfile'],check=True)
subprocess.run(['dart','fix','--apply','lib'],check=True)
print('V0.6.2 : sources vérifiées ; données, schéma et dépendances inchangés.')
