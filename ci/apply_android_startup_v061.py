"""Apply only the Android SQLite startup hotfix and its version increment.

The database filename, schema version, migration and all UI code are unchanged.
Run against the clean V0.6.0 source, or the already-patched V0.6.1 source.
"""
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    content = file.read_text(encoding='utf-8')
    if old in content:
        if content.count(old) != 1:
            raise RuntimeError(f'Ambiguous patch target: {path}')
        file.write_text(content.replace(old, new, 1), encoding='utf-8')
    elif new not in content:
        raise RuntimeError(f'Unexpected source; refuse to modify {path}')


replace_once(
    'lib/services/local_store.dart',
    "          await db.execute('PRAGMA busy_timeout = 5000');",
    "          // busy_timeout returns a row, even when assigning a value.\n"
    "          // Android execSQL rejects row-returning statements; use rawQuery.\n"
    "          await db.rawQuery('PRAGMA busy_timeout = 5000');",
)
replace_once('pubspec.yaml', 'version: 0.6.0+14', 'version: 0.6.1+15')
replace_once(
    'lib/services/principal_api.dart',
    "mobileVersion = '0.6.0'", "mobileVersion = '0.6.1'",
)
print('V0.6.1: rawQuery for busy_timeout; schema, migrations and UI unchanged.')
