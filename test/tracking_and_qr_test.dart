import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/connection_qr.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';

const config = PrincipalConfig(
  host: '192.0.2.1',
  port: 47831,
  teacher: 'Synthetic teacher',
  code: '123456',
  principalId: 'TEST',
);
TeacherEvent sample(String id) => TeacherEvent(
  id: id,
  type: 'attendance',
  teacher: config.teacher,
  studentId: 'SYNTHETIC',
  classId: 'A',
  createdAt: DateTime(2026, 10, 4),
  payload: {'status': 'Absence'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  group('QR connection', () {
    test('Principal QR carries address port code and identity', () {
      final q = ConnectionQr.parse(
        'GESTCOURS|192.168.1.22:47832|123456|GC-SYNTHETIC',
      );
      expect(q.address, '192.168.1.22:47832');
      expect(q.code, '123456');
      expect(q.principalId, 'GC-SYNTHETIC');
    });
    test('older GESTCOURS QR remains supported', () {
      final q = ConnectionQr.parse('GESTCOURS|192.168.1.22|123456');
      expect(q.principalId, '');
    });
    test('older ECOLEPRO QR keeps its nondefault port', () {
      final q = ConnectionQr.parse('ECOLEPRO|192.168.1.22|47832|Test|123456');
      expect(q.address, '192.168.1.22:47832');
    });
    for (final raw in [
      'other|192.168.1.1|123456',
      'GESTCOURS|https://example.test|123456',
      'GESTCOURS|user:secret@127.0.0.1|123456',
      'GESTCOURS|192.168.1.1/other|123456',
      'GESTCOURS|192.168.1.1?x=1|123456',
      'GESTCOURS|192.168.1.1|12345',
      'GESTCOURS|192.168.1.1:65536|123456',
      'GESTCOURS||123456',
      'ECOLEPRO|host|0|test|123456',
    ]) {
      test(
        'rejects invalid QR $raw',
        () => expect(() => ConnectionQr.parse(raw), throwsFormatException),
      );
    }
  });
  group('display-only reset', () {
    late Directory dir;
    late LocalStore store;
    LocalStore create() => LocalStore(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/test.db',
      legacyValues: const {},
    );
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gestcours_reset');
      store = create();
      await store.activateSession(config);
      await store.enqueueMany([
        sample('pending'),
        sample('received'),
        sample('accepted'),
        sample('refused'),
      ]);
      await store.resolveQueue(
        acknowledgedIds: {'received', 'accepted'},
        rejectedReasons: {'refused': 'Test'},
      );
      await store.updateTransmissionStatuses({
        'accepted': {'status': 'accepted'},
      });
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    test('all counters reset but pending and history remain intact', () async {
      final before = jsonDecode(await store.exportBundle()) as Map;
      expect(await store.resetTransmissionDashboard(), 3);
      expect(await store.loadDashboardHistory(), isEmpty);
      expect((await store.loadQueue()).single.id, 'pending');
      expect((await store.loadTransmissionHistory()).length, 3);
      final after = jsonDecode(await store.exportBundle()) as Map;
      expect(after['events'], before['events']);
      expect(after['logs'], before['logs']);
    });
    test('reset survives close and reopening', () async {
      await store.resetTransmissionDashboard();
      await store.close();
      store = create();
      expect(await store.loadDashboardHistory(), isEmpty);
      expect((await store.loadQueue()).length, 1);
    });
    test('new Principal decision reappears after reset', () async {
      await store.resetTransmissionDashboard();
      await store.updateTransmissionStatuses({
        'received': {'status': 'accepted'},
      });
      expect((await store.loadDashboardHistory()).single.id, 'received');
      expect((await store.loadTransmissionHistory()).length, 3);
    });
    test('pending work acknowledged later becomes visible', () async {
      await store.resetTransmissionDashboard();
      await store.resolveQueue(acknowledgedIds: {'pending'});
      expect((await store.loadDashboardHistory()).single.id, 'pending');
      expect(await store.loadQueue(), isEmpty);
    });
    test(
      'new entries remain visible and repeated resets do not delete',
      () async {
        await store.resetTransmissionDashboard();
        await store.enqueue(sample('new'));
        await store.resetTransmissionDashboard();
        expect((await store.loadQueue()).map((e) => e.id).toSet(), {
          'pending',
          'new',
        });
      },
    );
    test(
      'export restore retain reset without cloning device identity',
      () async {
        await store.resetTransmissionDashboard();
        final backup = await store.exportBundle();
        final restored = LocalStore(
          factory: databaseFactoryFfiNoIsolate,
          databasePath: '${dir.path}/restored.db',
          legacyValues: const {},
        );
        try {
          final device = await restored.getOrCreateDeviceId();
          await restored.importBundle(backup);
          expect(await restored.loadDashboardHistory(), isEmpty);
          expect((await restored.loadQueue()).single.id, 'pending');
          expect(await restored.getOrCreateDeviceId(), device);
        } finally {
          await restored.close();
        }
      },
    );
    test('reset does not affect another teacher or Principal', () async {
      await store.resetTransmissionDashboard();
      await store.resolveQueue(acknowledgedIds: {'pending'});
      const other = PrincipalConfig(
        host: '192.0.2.2',
        port: 47831,
        teacher: 'Other',
        code: '654321',
        principalId: 'OTHER',
      );
      await store.activateSession(other);
      final e = TeacherEvent(
        id: 'other',
        type: 'attendance',
        teacher: 'Other',
        studentId: 'X',
        classId: 'X',
        createdAt: DateTime(2026, 10, 4),
        payload: const {},
      );
      await store.enqueue(e);
      await store.resolveQueue(acknowledgedIds: {'other'});
      expect((await store.loadDashboardHistory()).single.id, 'other');
      await store.resetTransmissionDashboard();
      await store.activateSession(config);
      expect((await store.loadDashboardHistory()).single.id, 'pending');
    });
    test('SQLite opening fix retained', () {
      final source = File('lib/services/local_store.dart').readAsStringSync();
      expect(source, contains("rawQuery('PRAGMA busy_timeout = 5000')"));
      expect(source, isNot(contains('DROP TABLE')));
    });
    test('technical footer removed and diagnostic remains available', () {
      final source = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(source, isNot(contains('Informations techniques')));
      expect(source, isNot(contains('Stockage local transactionnel SQLite')));
      expect(source, contains("child: Text('Diagnostic')"));
    });
  });
}
