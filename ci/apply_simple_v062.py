"""V0.6.2 sources are committed. Validate the base and apply idempotent lint fixes."""
from pathlib import Path
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
p = Path('lib/screens/followup_screen.dart')
s = p.read_text()
s = s.replace("if (mounted && request == generation)\n        setState(() => error = userMessage(e));", "if (mounted && request == generation) {\n        setState(() => error = userMessage(e));\n      }")
s = s.replace("if (mounted)\n        ScaffoldMessenger.of(\n          context,\n        ).showSnackBar(SnackBar(content: Text(userMessage(e))));", "if (mounted) {\n        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));\n      }")
p.write_text(s)
p = Path('lib/services/user_message.dart')
s = p.read_text().replace("if (text.contains('qr'))\n    return 'Ce QR n’est pas un code de connexion GESTCOURS valide.';", "if (text.contains('qr')) {\n    return 'Ce QR n’est pas un code de connexion GESTCOURS valide.';\n  }")
p.write_text(s)
p = Path('test/followup_connection_test.dart')
s = p.read_text()
if 'HttpOverrides.global = null;' not in s:
    s = s.replace('final server = await HttpServer.bind(', 'final previousOverrides = HttpOverrides.global;\n      HttpOverrides.global = null;\n      final server = await HttpServer.bind(', 1)
    s = s.replace('await server.close(force: true);', 'await server.close(force: true);\n        HttpOverrides.global = previousOverrides;', 1)
p.write_text(s)
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
