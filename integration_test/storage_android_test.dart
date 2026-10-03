import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/main.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/school_data.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';

// Run ONLY on the isolated CI emulator. All identities and values are synthetic.
const cfg = PrincipalConfig(host: '192.0.2.1', port: 47831,
    teacher: 'Synthetic teacher', code: '123456', principalId: 'GC-CI');
SyncSnapshot snapshot() => SyncSnapshot.fromJson({
  'protocolVersion': 6, 'principalId': 'GC-CI', 'teacher': cfg.teacher,
  'schoolName': 'Synthetic test school', 'classes': [], 'students': [],
});
TeacherEvent event(String id) => TeacherEvent(
  id: id, type: 'attendance', teacher: cfg.teacher,
  studentId: 'SYNTHETIC-STUDENT', classId: 'SYNTHETIC-CLASS',
  createdAt: DateTime(2026, 10, 3),
  payload: {'date': '03/10/2026', 'status': 'Absence'},
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late String testPath;
  final stores = <LocalStore>[];
  LocalStore store({Map<String, Object>? legacy = const {}}) {
    final value = LocalStore(databasePath: testPath, legacyValues: legacy);
    stores.add(value);
    return value;
  }
  setUp(() async {
    expect(Platform.isAndroid, isTrue);
    testPath = '${await getDatabasesPath()}/gestcours_ci_${DateTime.now().microsecondsSinceEpoch}.db';
  });
  tearDown(() async {
    for (final value in stores) { await value.close(); }
    stores.clear();
    await deleteDatabase(testPath);
  });
  testWidgets('native Android reproduces the old execute error and accepts rawQuery', (tester) async {
    final db = await openDatabase(testPath);
    try {
      await expectLater(db.execute('PRAGMA busy_timeout = 5000'),
          throwsA(isA<DatabaseException>()));
      final result = await db.rawQuery('PRAGMA busy_timeout = 5000');
      expect(result, isNotEmpty);
      expect(result.first.values.first, 5000);
      expect((await db.rawQuery('PRAGMA busy_timeout')).first.values.first, 5000);
    } finally { await db.close(); }
  });
  testWidgets('real LocalStore opens and persists pending, received, refused records', (tester) async {
    var value = store();
    expect(await value.loadConfig(), isNull);
    await value.activateSession(cfg, snapshot());
    final device = await value.getOrCreateDeviceId();
    await value.enqueueMany([event('PENDING'), event('RECEIVED'), event('REFUSED')]);
    await value.resolveQueue(acknowledgedIds: {'RECEIVED'},
        rejectedReasons: {'REFUSED': 'Synthetic refusal'});
    final before = jsonDecode(await value.exportBundle());
    await value.close();
    value = store();
    expect((await value.loadConfig())!.principalId, cfg.principalId);
    expect(await value.getOrCreateDeviceId(), device);
    expect((await value.loadQueue()).single.id, 'PENDING');
    final history = await value.loadTransmissionHistory();
    expect(history.length, 2);
    expect(history.firstWhere((e) => e.id == 'RECEIVED').status, 'received');
    expect(history.firstWhere((e) => e.id == 'REFUSED').payload['_reviewNote'], 'Synthetic refusal');
    final after = jsonDecode(await value.exportBundle());
    expect(after['events'], before['events']);
    expect(after['meta'], before['meta']);
  });
  testWidgets('failed legacy opening recovers and migrates real native preferences only once', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, Object>{
      'principal_config_v1': jsonEncode(cfg.toJson()),
      'school_snapshot_v1': jsonEncode(snapshot().toJson()),
      'teacher_event_queue_v1': jsonEncode([event('LEGACY').toLocalJson()]),
      'teacher_event_transmission_v1': jsonEncode([event('LEGACY-RECEIVED').copyWithStatus('received').toLocalJson()]),
      'mobile_device_id_v1': 'SYNTHETIC-LEGACY-PHONE',
    };
    for (final e in values.entries) { await prefs.setString(e.key, e.value as String); }
    try {
      await expectLater(openDatabase(testPath, version: 1,
          onConfigure: (db) async { await db.execute('PRAGMA busy_timeout = 5000'); }),
          throwsA(isA<DatabaseException>()));
      var value = store(legacy: null);
      expect((await value.loadQueue()).single.id, 'LEGACY');
      expect((await value.loadTransmissionHistory()).single.id, 'LEGACY-RECEIVED');
      expect(await value.getOrCreateDeviceId(), 'SYNTHETIC-LEGACY-PHONE');
      await value.resolveQueue(acknowledgedIds: {'LEGACY'});
      await value.close();
      value = store(legacy: null);
      expect(await value.loadQueue(), isEmpty);
      expect((await value.loadTransmissionHistory()).length, 2);
      for (final e in values.entries) { expect(prefs.get(e.key), e.value); }
    } finally {
      for (final key in values.keys) { await prefs.remove(key); }
    }
  });
  testWidgets('native transaction rollback does not leave half a class saved', (tester) async {
    final value = store();
    await value.activateSession(cfg, snapshot());
    await value.enqueue(event('EXISTS'));
    await expectLater(value.enqueueMany([event('NEW'), event('EXISTS')]),
        throwsA(isA<DatabaseException>()));
    expect((await value.loadQueue()).map((e) => e.id).toList(), ['EXISTS']);
  });
  testWidgets('all four SQLite safety settings are applied by the real store', (tester) async {
    final value = store();
    await value.loadConfig();
    final db = await openDatabase(testPath);
    expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);
    expect((await db.rawQuery('PRAGMA journal_mode')).first.values.first, 'wal');
    expect((await db.rawQuery('PRAGMA synchronous')).first.values.first, 2);
    expect((await db.rawQuery('PRAGMA busy_timeout')).first.values.first, 5000);
    expect(await db.getVersion(), 1);
  });
  testWidgets('normal application startup reaches setup instead of protection screen', (tester) async {
    await tester.pumpWidget(const EcoleGestionProfApp());
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('Protection des données'), findsNothing);
    expect(find.text('Connexion au Principal'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
