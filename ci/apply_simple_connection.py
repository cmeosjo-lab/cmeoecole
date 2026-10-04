"""Validate committed V0.6.2 sources and finish user-facing message cleanup."""
from pathlib import Path
import subprocess
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
assert 'resetDashboardCounters' in Path('lib/services/local_store.dart').read_text()
assert Path('test/pairing_network_test.dart').exists()
p=Path('lib/screens/home_screen.dart')
s=p.read_text().replace("Text('Adresse non modifiée : $e')", "Text('Adresse non modifiée. ${friendlyMessage(e)}')")
p.write_text(s)
p=Path('lib/services/friendly_message.dart')
s=p.read_text().replace(r'HTTP|https?://|SocketException|DatabaseException|PRAGMA', r'HTTP|https?://|SocketException|DatabaseException|PRAGMA|\(\d{3}\)|<!?\w|protocole')
p.write_text(s)
subprocess.run(['flutter','pub','get','--enforce-lockfile'],check=True)
subprocess.run(['dart','fix','--apply','lib'],check=True)
print('V0.6.2 : messages simplifiés ; données, schéma et dépendances inchangés.')
