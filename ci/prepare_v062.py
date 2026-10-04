"""Prepare idempotently, formatting before lint fixes are calculated."""
from pathlib import Path
import runpy
import subprocess
version = Path('pubspec.yaml').read_text(encoding='utf-8')
if 'version: 0.6.1+15' in version:
    runpy.run_path('ci/apply_v062.py', run_name='__main__')
elif 'version: 0.6.2+16' not in version:
    raise SystemExit('Base mobile inattendue ; arrêt sans modification')
# Keep widget layout tests independent of real-time FFI I/O. The same suite
# still executes all SQLite persistence/reset tests and native Android tests.
p = Path('test/followup_connection_test.dart')
s = p.read_text(encoding='utf-8')
old = 'await tester.pumpWidget(MaterialApp(home:FollowUpScreen(store:store)));'
if old in s:
    s = "import 'widget_followup_store.dart';\n" + s
    s = s.replace(old, "final widgetStore = WidgetFollowUpStore([sample('P')], [sample('R').copyWithStatus('received')]);\n  await tester.pumpWidget(MaterialApp(home:FollowUpScreen(store:widgetStore)));", 1)
    p.write_text(s, encoding='utf-8')
subprocess.run(['dart', 'format', 'lib', 'test', 'integration_test'], check=True)
