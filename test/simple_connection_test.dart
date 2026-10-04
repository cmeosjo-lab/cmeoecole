import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/connection_qr.dart';
import 'package:ecole_gestion_prof_mobile/services/friendly_message.dart';
import 'package:ecole_gestion_prof_mobile/screens/setup_screen.dart';

const config = PrincipalConfig(
  host: '127.0.0.1',
  port: 47831,
  teacher: 'Synthetic',
  code: '123456',
  principalId: 'GC-SYNTHETIC',
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
  LocalStore reopen() => LocalStore(
    factory: databaseFactoryFfiNoIsolate,
    databasePath: '${dir.path}/test.db',
    legacyValues: const {},
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gestcours_simple');
    store = reopen();
    await store.activateSession(config);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> populate() async {
    await store.enqueueMany([
      sample('pending'),
      sample('received'),
      sample('accepted'),
      sample('refused'),
    ]);
    await store.resolveQueue(
      acknowledgedIds: {'received', 'accepted'},
      rejectedReasons: {'refused': 'Synthetic refusal'},
    );
    await store.updateTransmissionStatuses({
      'accepted': {'status': 'accepted'},
    });
  }

  test(
    'reset hides counters only and retains full history and pending work',
    () async {
      await populate();
      final history = await store.loadTransmissionHistory();
      final pending = await store.loadQueue();
      expect((await store.loadDashboardHistory()).length, 3);
      expect(await store.resetDashboardCounters(), 3);
      expect(await store.loadDashboardHistory(), isEmpty);
      expect(
        jsonEncode(
          (await store.loadTransmissionHistory())
              .map((e) => e.toLocalJson())
              .toList(),
        ),
        jsonEncode(history.map((e) => e.toLocalJson()).toList()),
      );
      expect((await store.loadQueue()).single.id, pending.single.id);
    },
  );
  test('a decision received after reset becomes visible again', () async {
    await populate();
    await store.resetDashboardCounters();
    await store.updateTransmissionStatuses({
      'received': {'status': 'accepted'},
    });
    final shown = await store.loadDashboardHistory();
    expect(shown.single.id, 'received');
    expect(shown.single.status, 'accepted');
    expect((await store.loadTransmissionHistory()).length, 3);
  });
  test(
    'reset persists after restart, late events with old dates remain visible',
    () async {
      await populate();
      await store.resetDashboardCounters();
      await store.close();
      store = reopen();
      expect(await store.loadDashboardHistory(), isEmpty);
      await store.resolveQueue(acknowledgedIds: {'pending'});
      expect((await store.loadDashboardHistory()).single.id, 'pending');
    },
  );
  test('reset stays isolated between teacher sessions', () async {
    await populate();
    await store.resolveQueue(acknowledgedIds: {'pending'});
    await store.resetDashboardCounters();
    const other = PrincipalConfig(
      host: '127.0.0.1',
      port: 47831,
      teacher: 'Other',
      code: '654321',
      principalId: 'GC-OTHER',
    );
    await store.activateSession(other);
    await store.resetDashboardCounters();
    await store.activateSession(config);
    expect(await store.loadDashboardHistory(), isEmpty);
    expect((await store.loadTransmissionHistory()).length, 4);
  });
  test('reset and queue additions cannot remove unconfirmed work', () async {
    await populate();
    await Future.wait([
      store.resetDashboardCounters(),
      store.enqueue(sample('concurrent')),
    ]);
    expect((await store.loadQueue()).map((e) => e.id).toSet(), {
      'pending',
      'concurrent',
    });
  });
  test('repeated reset is harmless', () async {
    await populate();
    await store.resetDashboardCounters();
    await store.resetDashboardCounters();
    expect(await store.loadDashboardHistory(), isEmpty);
    expect((await store.loadQueue()).length, 1);
  });
  test('QR JSON preserves non-default port and expected school identity', () {
    final qr = ConnectionQr.parse(
      jsonEncode({
        'app': 'GESTCOURS',
        'v': 1,
        'host': '192.168.1.20',
        'port': 47832,
        'code': '123456',
        'principalId': 'GC-TEST',
      }),
    );
    expect(qr.address, '192.168.1.20:47832');
    expect(qr.code, '123456');
    expect(qr.principalId, 'GC-TEST');
  });
  test('legacy QR preserves port and teacher code', () {
    expect(
      ConnectionQr.parse('ECOLEPRO|192.168.1.20|47832|Test|123456').address,
      '192.168.1.20:47832',
    );
    expect(
      ConnectionQr.parse('GESTCOURS|192.168.1.20:47832|123456').code,
      '123456',
    );
  });
  test('malformed QR and unsafe addresses rejected', () {
    for (final v in [
      'hello',
      'GESTCOURS|https://invalid.example|123456',
      'GESTCOURS|user:pw@192.168.1.20|123456',
      'GESTCOURS|192.168.1.20/path|123456',
      'ECOLEPRO|192.168.1.20|0|Test|123456',
      'GESTCOURS|192.168.1.20|123',
    ]) {
      expect(() => ConnectionQr.parse(v), throwsFormatException);
    }
  });
  test('native errors are translated, not exposed to the teacher', () {
    for (final e in [
      'DatabaseException PRAGMA busy_timeout',
      'SocketException: http://example.com',
      TimeoutException('secret'),
      const FormatException('SQL query'),
    ]) {
      final s = friendlyMessage(e);
      expect(s, isNot(contains('Exception')));
      expect(s, isNot(contains('PRAGMA')));
      expect(s, isNot(contains('secret')));
      expect(s, isNot(contains('http://')));
    }
  });
  test(
    'pairing waits for admin and distinguishes refusal without authorizing',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var state = 'pending';
      final sub = server.listen((r) async {
        expect(r.uri.queryParameters['deviceId'], 'PHONE-TEST');
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'ok': true,
            'protocolVersion': 6,
            'teacher': 'Synthetic',
            'port': server.port,
            'principalId': 'GC-SYNTHETIC',
            'deviceAuthorized': state == 'authorized',
            'deviceStatus': state,
          }),
        );
        await r.response.close();
      });
      try {
        const api = PrincipalApi();
        final address = '127.0.0.1:${server.port}';
        await expectLater(
          api.pairAddress(address, '123456', deviceId: 'PHONE-TEST'),
          throwsA(isA<PrincipalApprovalPending>()),
        );
        state = 'refused';
        await expectLater(
          api.pairAddress(address, '123456', deviceId: 'PHONE-TEST'),
          throwsA(
            isA<PrincipalApiException>().having(
              (e) => e.message,
              'message',
              contains('refusée'),
            ),
          ),
        );
        state = 'authorized';
        expect(
          (await api.pairAddress(
            address,
            '123456',
            deviceId: 'PHONE-TEST',
          )).principalId,
          'GC-SYNTHETIC',
        );
      } finally {
        await sub.cancel();
        await server.close(force: true);
      }
    },
  );
  testWidgets('QR entry is visible on a small screen without technical panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: SetupScreen(
          store: store,
          api: const PrincipalApi(),
          onConnected: (_) {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Scanner mon QR de connexion'), findsOneWidget);
    expect(find.text('Informations techniques'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('technical panels are absent, safe reset action is present', () {
    final s = File('lib/screens/home_screen.dart').readAsStringSync();
    expect(s, isNot(contains("Text('Informations techniques')")));
    expect(s, isNot(contains("Text('Diagnostic')")));
    expect(s, contains('Remettre les compteurs à zéro'));
    expect(s, isNot(contains('Stockage local transactionnel SQLite')));
  });
}
