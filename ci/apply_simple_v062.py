"""Keep production code unchanged. Visual tests use an immediate store;
real SQLite behavior is covered separately by unit and native Android tests.
"""
from pathlib import Path
assert 'version: 0.6.2+16' in Path('pubspec.yaml').read_text()
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
p=Path('test/followup_connection_test.dart')
s=p.read_text()
if 'class _WidgetFollowupStore' not in s:
    a=s.index("  testWidgets('followup fits")
    s=s[:a]+'''  testWidgets('followup fits a small screen and reset asks before archiving', (tester) async {
    final memory = _WidgetFollowupStore();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: FollowupScreen(store: memory)));
    await tester.pumpAndSettle();
    expect(find.text('Suivi des saisies'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('reset-followup')));
    await tester.pumpAndSettle();
    expect(find.text('Remettre le suivi à zéro ?'), findsOneWidget);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(memory.resetCalls, 0);
    await tester.tap(find.byKey(const ValueKey('reset-followup')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remettre à zéro'));
    await tester.pumpAndSettle();
    expect(memory.resetCalls, 1);
    expect((await memory.loadFollowup()).single.id, 'pending');
    expect((await memory.loadFollowup(archived: true)).single.id, 'received');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, timeout: const Timeout(Duration(minutes: 1)));
}

// Immediate fixture for screen geometry and confirmation only; never used by the app.
class _WidgetFollowupStore extends LocalStore {
  int resetCalls = 0;
  @override
  Future<List<TeacherEvent>> loadFollowup({bool archived = false}) async {
    final received = ev('received').copyWithStatus('received');
    if (archived) return resetCalls > 0 ? [received] : [];
    return [ev('pending'), if (resetCalls == 0) received];
  }
  @override
  Future<int> resetFollowup() async { resetCalls++; return 1; }
}
'''
p.write_text(s)
