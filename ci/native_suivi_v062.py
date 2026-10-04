from pathlib import Path
p = Path('integration_test/sqlite_startup_test.dart'); s = p.read_text()
if 'reset tracking on native Android preserves work' not in s:
    pos=s.rfind('\n}')
    s=s[:pos]+'''
  testWidgets('reset tracking on native Android preserves work and late decisions', (tester) async {
    var store = openStore();
    await store.activateSession(config);
    await store.enqueueMany([sample('PENDING'), sample('RECEIVED')]);
    await store.resolveQueue(acknowledgedIds: {'RECEIVED'});
    final device = await store.getOrCreateDeviceId();
    expect(await store.resetDashboardTracking(), 1);
    expect(await store.loadDashboardHistory(), isEmpty);
    expect((await store.loadQueue()).single.id, 'PENDING');
    await store.close();
    store = openStore();
    expect(await store.getOrCreateDeviceId(), device);
    expect((await store.loadTransmissionHistory()).single.id, 'RECEIVED');
    expect(await store.loadDashboardHistory(), isEmpty);
    await store.updateTransmissionStatuses({'RECEIVED': {'status': 'accepted'}});
    expect((await store.loadDashboardHistory()).single.status, 'accepted');
    expect((await store.loadQueue()).single.id, 'PENDING');
  });
'''+s[pos:]
    p.write_text(s)
