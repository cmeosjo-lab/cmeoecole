import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';

const config = PrincipalConfig(
  host: '192.0.2.1',
  port: 47831,
  teacher: 'Synthetic teacher',
  code: '123456',
  principalId: 'SYNTHETIC-PRINCIPAL',
);
TeacherEvent sample(String id) => TeacherEvent(
  id: id,
  type: 'attendance',
  teacher: config.teacher,
  studentId: 'SYNTHETIC-STUDENT',
  classId: 'SYNTHETIC-CLASS',
  createdAt: DateTime(2026, 10, 3),
  payload: {'date': '03/10/2026', 'status': 'Absence'},
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String path;
  final stores = <LocalStore>[];
  setUp(() async {
    path =
        '${await getDatabasesPath()}/gestcours_native_test_${DateTime.now().microsecondsSinceEpoch}.db';
  });
  tearDown(() async {
    for (final store in stores) {
      await store.close();
    }
    stores.clear();
    // Only synthetic test databases are removed, never gestcours_v24.db.
    expect(path, contains('/gestcours_native_test_'));
    await deleteDatabase(path);
  });
  LocalStore openStore({Map<String, Object>? legacy = const {}}) {
    final store = LocalStore(databasePath: path, legacyValues: legacy);
    stores.add(store);
    return store;
  }

  testWidgets('Android reproduces the old execute error and accepts rawQuery', (
    tester,
  ) async {
    final db = await openDatabase(path);
    try {
      await db.execute('CREATE TABLE sentinel (value TEXT NOT NULL)');
      await db.insert('sentinel', {'value': 'preserve me'});
      await expectLater(
        db.execute('PRAGMA busy_timeout = 5000'),
        throwsA(isA<DatabaseException>()),
      );
      final result = await db.rawQuery('PRAGMA busy_timeout = 5000');
      expect(result.single.values.single, 5000);
      expect(
        (await db.rawQuery('PRAGMA busy_timeout')).single.values.single,
        5000,
      );
      expect((await db.query('sentinel')).single['value'], 'preserve me');
      expect(
        (await db.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
    } finally {
      await db.close();
    }
  });

  testWidgets(
    'Native LocalStore opens and retains pending work after restart',
    (tester) async {
      var store = openStore();
      expect(await store.loadConfig(), isNull);
      await store.activateSession(config);
      final device = await store.getOrCreateDeviceId();
      await store.enqueueMany([
        sample('PENDING'),
        sample('RECEIVED'),
        sample('REFUSED'),
      ]);
      await store.resolveQueue(
        acknowledgedIds: {'RECEIVED'},
        rejectedReasons: {'REFUSED': 'Synthetic refusal'},
      );
      await store.appendSyncLog('Synthetic log');
      final before = await store.exportBundle();
      await store.close();
      store = openStore();
      expect((await store.loadConfig())!.principalId, config.principalId);
      expect(await store.getOrCreateDeviceId(), device);
      expect((await store.loadQueue()).single.id, 'PENDING');
      expect((await store.loadTransmissionHistory()).map((e) => e.id).toSet(), {
        'RECEIVED',
        'REFUSED',
      });
      expect(await store.exportBundle(), before);
    },
  );

  testWidgets(
    'Native legacy preferences migrate once without clearing originals',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final legacy = <String, String>{
        'principal_config_v1': jsonEncode(config.toJson()),
        'teacher_event_queue_v1': jsonEncode([
          sample('LEGACY-PENDING').toLocalJson(),
        ]),
        'teacher_event_transmission_v1': jsonEncode([
          sample('LEGACY-HISTORY').copyWithStatus('accepted').toLocalJson(),
        ]),
        'mobile_device_id_v1': 'PHONE-SYNTHETIC-ORIGINAL',
      };
      try {
        for (final entry in legacy.entries) {
          await prefs.setString(entry.key, entry.value);
        }
        var store = openStore(legacy: null);
        expect((await store.loadQueue()).single.id, 'LEGACY-PENDING');
        expect(
          (await store.loadTransmissionHistory()).single.status,
          'accepted',
        );
        expect(await store.getOrCreateDeviceId(), 'PHONE-SYNTHETIC-ORIGINAL');
        for (final entry in legacy.entries) {
          expect(prefs.getString(entry.key), entry.value);
        }
        await store.enqueue(sample('NEW-PENDING'));
        await store.close();
        store = openStore(legacy: null);
        expect((await store.loadQueue()).map((e) => e.id).toSet(), {
          'LEGACY-PENDING',
          'NEW-PENDING',
        });
        expect((await store.loadTransmissionHistory()).length, 1);
      } finally {
        for (final key in legacy.keys) {
          await prefs.remove(key);
        }
      }
    },
  );

  testWidgets(
    'An old failing configure does not require deleting the database',
    (tester) async {
      var store = openStore();
      await store.activateSession(config);
      await store.enqueue(sample('PRESERVED-AFTER-FAILURE'));
      final before = await store.exportBundle();
      await store.close();
      await expectLater(
        openDatabase(
          path,
          onConfigure: (db) async {
            await db.execute('PRAGMA busy_timeout = 5000');
          },
        ),
        throwsA(isA<DatabaseException>()),
      );
      store = openStore();
      expect(await store.exportBundle(), before);
      expect((await store.loadQueue()).single.id, 'PRESERVED-AFTER-FAILURE');
    },
  );
  testWidgets(
    'reset tracking on native Android preserves work and late decisions',
    (tester) async {
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
      await store.updateTransmissionStatuses({
        'RECEIVED': {'status': 'accepted'},
      });
      expect((await store.loadDashboardHistory()).single.status, 'accepted');
      expect((await store.loadQueue()).single.id, 'PENDING');
    },
  );
}
