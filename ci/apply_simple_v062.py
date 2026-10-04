"""Separate visual and disk fixtures; all production and native tests remain intact."""
from pathlib import Path
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
p=Path('test/followup_connection_test.dart')
s=p.read_text()
if "  testWidgets('followup fits" in s:
    start=s.index("  testWidgets('followup fits")
    helper=s[s.index('TeacherEvent ev('):s.index('void main()')]
    imports="""import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/screens/followup_screen.dart';
"""
    Path('test/followup_screen_test.dart').write_text(imports+helper+'void main() {\n'+s[start:])
    s=s[:start]+'}\n'
    s=s.replace("import 'package:flutter/material.dart';\n",'')
    s=s.replace("import 'package:ecole_gestion_prof_mobile/screens/followup_screen.dart';\n",'')
    p.write_text(s)
