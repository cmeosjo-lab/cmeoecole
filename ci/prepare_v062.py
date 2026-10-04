"""Prepare idempotently, formatting before lint fixes are calculated."""
from pathlib import Path
import runpy
import subprocess
version = Path('pubspec.yaml').read_text(encoding='utf-8')
if 'version: 0.6.1+15' in version:
    runpy.run_path('ci/apply_v062.py', run_name='__main__')
elif 'version: 0.6.2+16' not in version:
    raise SystemExit('Base mobile inattendue ; arrêt sans modification')
subprocess.run(['dart', 'format', 'lib', 'test', 'integration_test'], check=True)
