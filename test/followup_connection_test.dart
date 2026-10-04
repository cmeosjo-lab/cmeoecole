import 'widget_followup_store.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/models/pairing_code.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/user_message.dart';
import 'package:ecole_gestion_prof_mobile/screens/followup_screen.dart';

const config = PrincipalConfig(
  host: '127.0.0.1',
  port: 47831,
  teacher: 'Test',
  code: '123456',
  principalId: 'TEST',
);
TeacherEvent sample(String id) => TeacherEvent(
  id: id,
  type: 'attendance',
  teacher: config.teacher,
  studentId: 'S',
  classId: 'C',
  createdAt: DateTime(2026, 10, 4),
  payload: {'date': '04/10/2026', 'status': 'Absence'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  LocalStore open() => LocalStore(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: '${dir.path}/test.db',
    legacyValues: const {},
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gestcours_followup');
    store = open();
    await store.activateSession(config);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed() async {
    await store.enqueueMany([
      sample('P'),
      sample('R'),
      sample('A'),
      sample('F'),
    ]);
    await store.resolveQueue(
      acknowledgedIds: {'R', 'A'},
      rejectedReasons: {'F': 'Motif de test'},
    );
    await store.updateTransmissionStatuses({
      'A': {'status': 'accepted'},
    });
  }

  test(
    'reset archives transmitted states, never pending work or payloads',
    () async {
      await seed();
      final before = jsonDecode(await store.exportBundle()) as Map;
      await store.resetFollowUp();
      expect((await store.loadQueue()).single.id, 'P');
      expect(await store.loadFollowUpHistory(), isEmpty);
      expect((await store.loadFollowUpHistory(archived: true)).length, 3);
      final after = jsonDecode(await store.exportBundle()) as Map;
      expect(after['events'], before['events']);
      expect(after['logs'], before['logs']);
      expect((await store.loadConfig())!.toJson(), config.toJson());
    },
  );
  test('new administrative decisions reappear after a reset', () async {
    await seed();
    await store.resetFollowUp();
    await store.updateTransmissionStatuses({
      'R': {'status': 'refused', 'reviewNote': 'Décision nouvelle'},
    });
    final v = await store.loadFollowUpHistory();
    expect(v.single.id, 'R');
    expect(v.single.status, 'refused');
    expect(v.single.payload['_reviewNote'], 'Décision nouvelle');
  });
  test('new transmissions after a reset are counted', () async {
    await seed();
    await store.resetFollowUp();
    await store.resolveQueue(acknowledgedIds: {'P'});
    expect((await store.loadFollowUpHistory()).single.id, 'P');
  });
  test('reset survives closing and reopening the same database', () async {
    await seed();
    await store.resetFollowUp();
    await store.close();
    store = open();
    expect(await store.loadFollowUpHistory(), isEmpty);
    expect((await store.loadTransmissionHistory()).length, 3);
    expect((await store.loadQueue()).length, 1);
  });
  test('reset is idempotent and isolated per teacher and Principal', () async {
    await seed();
    await store.resolveQueue(acknowledgedIds: {'P'});
    await store.resetFollowUp();
    await store.resetFollowUp();
    const other = PrincipalConfig(
      host: '127.0.0.2',
      port: 47831,
      teacher: 'Test',
      code: '123456',
      principalId: 'OTHER',
    );
    await store.activateSession(other);
    await store.enqueue(sample('OTHER'));
    await store.resolveQueue(acknowledgedIds: {'OTHER'});
    expect((await store.loadFollowUpHistory()).single.id, 'OTHER');
    await store.activateSession(config);
    expect(await store.loadFollowUpHistory(), isEmpty);
    expect((await store.loadFollowUpHistory(archived: true)).length, 4);
  });
  test('backup preserves all archived records and their visibility', () async {
    await seed();
    await store.resetFollowUp();
    final backup = await store.exportBundle();
    final restored = LocalStore(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/restored.db',
      legacyValues: const {},
    );
    try {
      await restored.importBundle(backup);
      expect(await restored.loadFollowUpHistory(), isEmpty);
      expect((await restored.loadTransmissionHistory()).length, 3);
      expect((await restored.loadQueue()).single.id, 'P');
    } finally {
      await restored.close();
    }
  });
  test('concurrent reset and new work keep every event', () async {
    await seed();
    await Future.wait([store.resetFollowUp(), store.enqueue(sample('NEW'))]);
    expect((await store.loadQueue()).map((e) => e.id).toSet(), {'P', 'NEW'});
    expect((await store.loadTransmissionHistory()).length, 3);
  });
  test('QR preserves port and optional Principal binding', () {
    final q = PairingCode.parse('GESTCOURS|192.168.1.5:47832|123456|GC-TEST');
    expect(q.address, '192.168.1.5:47832');
    expect(q.code, '123456');
    expect(q.principalId, 'GC-TEST');
    expect(
      PairingCode.parse('ECOLEPRO|192.168.1.5|47832|Test|123456').address,
      '192.168.1.5:47832',
    );
  });
  test('malformed QR never becomes a connection', () {
    for (final value in [
      'https://example.com',
      'GESTCOURS|user@host|123456',
      'GESTCOURS|host/path|123456',
      'GESTCOURS|host|abcd',
      'GESTCOURS|host:99999|123456',
      'GESTCOURS|host|123456|bad id',
      'GESTCOURS|host|123456|a|b',
    ]) {
      expect(
        () => PairingCode.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
  test('technical exceptions are not displayed to the teacher', () {
    for (final value in [
      'DatabaseException: PRAGMA busy_timeout',
      'SocketException: errno 12',
      'HTTP 500 at /api/v1/events',
      'FormatException unexpected JSON',
    ]) {
      expect(userMessage(value), isNot(contains('Exception')));
      expect(userMessage(value), isNot(contains('PRAGMA')));
      expect(userMessage(value), isNot(contains('/api/')));
    }
  });
  testWidgets(
    'followup fits a small screen and does not offer a destructive reset',
    (tester) async {
      await tester.runAsync(seed);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final widgetStore = WidgetFollowUpStore(
        [sample('P')],
        [sample('R').copyWithStatus('received')],
      );
      await tester.pumpWidget(
        MaterialApp(home: FollowUpScreen(store: widgetStore)),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Remettre le suivi à zéro'), findsOneWidget);
      expect(find.text('Informations techniques'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Remettre le suivi à zéro'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Aucune donnée scolaire du Principal'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
