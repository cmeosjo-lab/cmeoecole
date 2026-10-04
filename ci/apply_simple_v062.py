"""Validate V0.6.2 and run disk IO outside the widget test's fake clock."""
from pathlib import Path
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
p = Path('test/followup_connection_test.dart')
s = p.read_text().replace('final previousOverrides = HttpOverrides.global;', 'final previousOverrides = HttpOverrides.current;')
s = s.replace('factory: databaseFactoryFfi,', 'factory: databaseFactoryFfiNoIsolate,')
s = s.replace('    await seed();\n    tester.view.physicalSize', '    await tester.runAsync(seed);\n    tester.view.physicalSize')
s = s.replace('    await tester.pumpWidget(MaterialApp(home: FollowupScreen(store: store)));\n    await tester.pumpAndSettle();', '    await tester.pumpWidget(MaterialApp(home: FollowupScreen(store: store)));\n    await tester.runAsync(() async {\n      await store.loadFollowup();\n      await Future<void>.delayed(const Duration(milliseconds: 100));\n    });\n    await tester.pumpAndSettle();')
s = s.replace('    expect((await store.loadFollowup()).length, 4);', '    expect((await tester.runAsync(() => store.loadFollowup()))!.length, 4);')
s = s.replace('    await tester.pumpWidget(const SizedBox.shrink());\n  });', '    await tester.pumpWidget(const SizedBox.shrink());\n  }, timeout: const Timeout(Duration(minutes: 1)));')
p.write_text(s)
