import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/pairing_code.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/user_messages.dart';
import 'package:ecole_gestion_prof_mobile/screens/entry_followup_screen.dart';

const config = PrincipalConfig(
  host: '192.168.1.20',
  port: 47831,
  teacher: 'Test',
  code: '123456',
  principalId: 'GC-TEST',
);
TeacherEvent entry(String id) => TeacherEvent(
  id: id,
  type: 'attendance',
  teacher: 'Test',
  studentId: 'S',
  classId: 'C',
  createdAt: DateTime(2026, 10, 4),
  payload: const {'date': '04/10/2026', 'status': 'Absence'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('QR address, port and Principal identity are preserved', () {
    final qr = PairingCode.parse('GESTCOURS|192.168.1.20:49001|123456|GC-TEST');
    expect(qr.address, '192.168.1.20:49001');
    expect(qr.code, '123456');
    expect(qr.principalId, 'GC-TEST');
    expect(
      PairingCode.parse('GESTCOURS|10.0.0.2|123456').address,
      '10.0.0.2:47831',
    );
    expect(
      PairingCode.parse('ECOLEPRO|172.16.1.2|49001|Test|123456').address,
      '172.16.1.2:49001',
    );
  });
  test('QR rejects remote login, malformed port, code and URL injection', () {
    for (final text in [
      'GESTCOURS|example.org|123456',
      'GESTCOURS|8.8.8.8|123456',
      'GESTCOURS|192.168.1.2:99999|123456',
      'GESTCOURS|192.168.1.2|12345',
      'GESTCOURS|192.168.1.2?x=x|123456',
      'OTHER|10.0.0.1|123456',
    ]) {
      expect(
        () => PairingCode.parse(text),
        throwsFormatException,
        reason: text,
      );
    }
  });
  test('Technical database errors are not shown to teachers', () {
    final text = userMessage(
      StateError('DatabaseException PRAGMA busy_timeout = 5000 SQLite'),
    );
    expect(text, contains('Ne désinstallez pas'));
    expect(text, isNot(contains('SQLite')));
    expect(text, isNot(contains('PRAGMA')));
  });
  group('Safe dashboard reset', () {
    late LocalStore store;
    late Directory dir;
    LocalStore create() => LocalStore(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/test.db',
      legacyValues: const {},
    );
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gestcours-reset');
      store = create();
      await store.activateSession(config);
    });
    tearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    Future<void> seed() async {
      await store.enqueueMany([
        entry('PENDING'),
        entry('RECEIVED'),
        entry('ACCEPTED'),
        entry('REFUSED'),
      ]);
      await store.resolveQueue(
        acknowledgedIds: {'RECEIVED', 'ACCEPTED'},
        rejectedReasons: {'REFUSED': 'test'},
      );
      await store.updateTransmissionStatuses({
        'ACCEPTED': {'status': 'accepted'},
      });
    }

    test(
      'Reset archives only terminal rows; no event or status is deleted',
      () async {
        await seed();
        final before = jsonDecode(await store.exportBundle()) as Map;
        expect(await store.resetDashboardHistory(), 2);
        final after = jsonDecode(await store.exportBundle()) as Map;
        expect(after['events'], before['events']);
        expect((await store.loadQueue()).single.id, 'PENDING');
        expect((await store.loadDashboardHistory()).single.id, 'RECEIVED');
        expect((await store.loadTransmissionHistory()).length, 3);
        expect(await store.resetDashboardHistory(), 0);
      },
    );
    test(
      'Hidden completed counters remain hidden after restart; new decisions stay visible',
      () async {
        await seed();
        await store.resetDashboardHistory();
        await store.close();
        store = create();
        expect((await store.archivedDashboardIds()).length, 2);
        await store.updateTransmissionStatuses({
          'RECEIVED': {'status': 'accepted'},
        });
        expect((await store.loadDashboardHistory()).single.id, 'RECEIVED');
      },
    );
    test('Reset is isolated by teacher and establishment', () async {
      await store.enqueue(entry('A'));
      await store.resolveQueue(
        acknowledgedIds: {},
        rejectedReasons: {'A': 'test'},
      );
      await store.resetDashboardHistory();
      const other = PrincipalConfig(
        host: '192.168.1.21',
        port: 47831,
        teacher: 'Test',
        code: '654321',
        principalId: 'GC-OTHER',
      );
      await store.activateSession(other);
      await store.enqueue(entry('B'));
      await store.resolveQueue(
        acknowledgedIds: {},
        rejectedReasons: {'B': 'test'},
      );
      expect(await store.archivedDashboardIds(), isEmpty);
      expect((await store.loadDashboardHistory()).single.id, 'B');
      await store.activateSession(config);
      expect(await store.loadDashboardHistory(), isEmpty);
    });
    test(
      'Reset and incoming work interleave without deleting the new entry',
      () async {
        await seed();
        await Future.wait([
          store.resetDashboardHistory(),
          store.enqueue(entry('NEW')),
        ]);
        expect((await store.loadQueue()).map((e) => e.id).toSet(), {
          'PENDING',
          'NEW',
        });
      },
    );
    testWidgets(
      'Follow-up screen fits small display and reset requires confirmation',
      (tester) async {
        await seed();
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(home: EntryFollowupScreen(store: store)),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Remettre les compteurs à zéro'));
        await tester.pumpAndSettle();
        expect(find.text('Remettre les compteurs à zéro ?'), findsOneWidget);
        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();
        expect(await store.archivedDashboardIds(), isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
  test(
    'HTTP pairing pending/accepted/refused states are distinguished',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var status = 'pending';
      server.listen((r) async {
        expect(r.uri.queryParameters['deviceId'], 'PHONE-TEST');
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'ok': true,
            'protocolVersion': 6,
            'teacher': 'Test',
            'port': server.port,
            'principalId': 'GC-TEST',
            'deviceAuthorized': status == 'accepted',
            'deviceStatus': status,
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
        status = 'accepted';
        expect(
          (await api.pairAddress(
            address,
            '123456',
            deviceId: 'PHONE-TEST',
          )).teacher,
          'Test',
        );
        status = 'refused';
        await expectLater(
          api.pairAddress(address, '123456', deviceId: 'PHONE-TEST'),
          throwsA(isA<PrincipalApiException>()),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}
