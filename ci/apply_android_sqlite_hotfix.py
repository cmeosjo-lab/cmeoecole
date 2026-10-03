"""Apply only the verified V0.6.1 Android SQLite startup correction."""
from pathlib import Path
import hashlib
import json

changes = {
    'lib/services/local_store.dart': (
        '693c65da91c6bf62c52a12f9b889480b6d8535f1182fac672604f592a108c503',
        "          await db.execute('PRAGMA busy_timeout = 5000');",
        "          // busy_timeout returns a row, even when setting the value.\n"
        "          // Android requires rawQuery for statements returning results.\n"
        "          await db.rawQuery('PRAGMA busy_timeout = 5000');",
    ),
    'lib/services/principal_api.dart': (
        '8c5c48425cacef52c08273e99500cf6c9f79090ef17b33d27193ba63af012b51',
        "mobileVersion = '0.6.0'", "mobileVersion = '0.6.1'",
    ),
    'pubspec.yaml': (
        '6fb7f3b313af1dc54ae5a913ba22a42e02171ed20b8efd6545f2089dcdc414ec',
        'version: 0.6.0+14', 'version: 0.6.1+15',
    ),
}
proof = {}
for name, (expected, before, after) in changes.items():
    p = Path(name)
    original = p.read_bytes()
    digest = hashlib.sha256(original).hexdigest()
    text = original.decode('utf-8')
    if before not in text and after in text:
        proof[name] = {'already_applied': True, 'sha256': digest}
        continue
    if digest != expected or text.count(before) != 1:
        raise SystemExit(f'Refusing to modify unexpected source: {name}')
    updated = text.replace(before, after).encode('utf-8')
    p.write_bytes(updated)
    proof[name] = {'before_sha256': digest, 'after_sha256': hashlib.sha256(updated).hexdigest()}
Path('dist').mkdir(exist_ok=True)
Path('dist/runtime-source-diff.json').write_text(json.dumps(proof, indent=2))
print('V0.6.1: one SQLite method fixed. Database file/schema and school functions unchanged.')
