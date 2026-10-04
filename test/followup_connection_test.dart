import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/connection_qr.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/user_message.dart';
import 'package:ecole_gestion_prof_mobile/screens/followup_screen.dart';

const cfg = PrincipalConfig(
  host: '192.168.1.20',
  port: 47831,
  teacher: 'Teacher',
  code: '123456',
  principalId: 'GC-SYNTHETIC',
);
TeacherEvent ev(String id) => TeacherEvent(
  id: id,
  type: 'attendance',
  teacher: 'Teacher',
  studentId: 'S1',
  classId: 'A1',
  createdAt: DateTime(2026, 1, 1),
  payload: {'status': 'Absence'},
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
    dir = await Directory.systemTemp.createTemp('gc-followup-');
    store = open();
    await store.activateSession(cfg);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> seed() async {
    await store.enqueueMany([
      ev('pending'),
      ev('received'),
      ev('accepted'),
      ev('refused'),
    ]);
    await store.resolveQueue(
      acknowledgedIds: {'received', 'accepted'},
      rejectedReasons: {'refused': 'À corriger'},
    );
    await store.updateTransmissionStatuses({
      'accepted': {'status': 'accepted'},
    });
  }

  test(
    'reset archives transmitted work but keeps unsent work visible',
    () async {
      await seed();
      final queue = await store.loadQueue();
      final history = await store.loadTransmissionHistory();
      expect(await store.resetFollowup(), 3);
      expect((await store.loadFollowup()).map((e) => e.id), ['pending']);
      expect((await store.loadFollowup(archived: true)).length, 3);
      expect(
        (await store.loadQueue()).map((e) => e.toLocalJson()),
        queue.map((e) => e.toLocalJson()),
      );
      expect(
        (await store.loadTransmissionHistory()).map((e) => e.toLocalJson()),
        history.map((e) => e.toLocalJson()),
      );
    },
  );
  test('reset survives reopening the unchanged SQLite schema', () async {
    await seed();
    await store.resetFollowup();
    await store.close();
    store = open();
    expect((await store.loadFollowup()).single.id, 'pending');
    expect((await store.loadFollowup(archived: true)).length, 3);
  });
  test('new Principal decision reappears even after reset', () async {
    await seed();
    await store.resetFollowup();
    await store.updateTransmissionStatuses({
      'received': {'status': 'refused', 'reviewNote': 'Correction demandée'},
    });
    expect((await store.loadFollowup()).map((e) => e.id).toSet(), {
      'pending',
      'received',
    });
    expect(
      (await store.loadFollowup())
          .singleWhere((e) => e.id == 'received')
          .payload['_reviewNote'],
      'Correction demandée',
    );
    expect((await store.loadFollowup(archived: true)).length, 2);
  });
  test('later receipt of old dated pending work is not hidden', () async {
    await seed();
    await store.resetFollowup();
    await store.resolveQueue(acknowledgedIds: {'pending'});
    expect((await store.loadFollowup()).single.id, 'pending');
    expect((await store.loadFollowup()).single.status, 'received');
  });
  test('reset is idempotent and empty reset leaves all work intact', () async {
    expect(await store.resetFollowup(), 0);
    await seed();
    await store.resetFollowup();
    await store.resetFollowup();
    expect((await store.loadQueue()).length, 1);
    expect((await store.loadTransmissionHistory()).length, 3);
  });
  test('concurrent enqueue and reset cannot delete new records', () async {
    await seed();
    await Future.wait([store.resetFollowup(), store.enqueue(ev('new'))]);
    expect((await store.loadQueue()).map((e) => e.id).toSet(), {
      'pending',
      'new',
    });
  });
  test('reset is scoped to the active Principal and teacher', () async {
    await store.enqueue(ev('one'));
    await store.resolveQueue(acknowledgedIds: {'one'});
    await store.resetFollowup();
    const another = PrincipalConfig(
      host: '192.168.1.21',
      port: 47831,
      teacher: 'Teacher',
      code: '654321',
      principalId: 'GC-OTHER',
    );
    await store.activateSession(another);
    await store.enqueue(ev('two'));
    await store.resolveQueue(acknowledgedIds: {'two'});
    expect((await store.loadFollowup()).single.id, 'two');
    await store.resetFollowup();
    await store.activateSession(cfg);
    expect(await store.loadFollowup(), isEmpty);
    expect((await store.loadFollowup(archived: true)).single.id, 'one');
  });
  test('reset metadata is kept by a backup restore', () async {
    await seed();
    await store.resetFollowup();
    final raw = await store.exportBundle();
    final restored = LocalStore(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/restored.db',
      legacyValues: const {},
    );
    try {
      await restored.importBundle(raw);
      expect((await restored.loadFollowup()).single.id, 'pending');
      expect((await restored.loadFollowup(archived: true)).length, 3);
    } finally {
      await restored.close();
    }
  });
  test('QR accepts current and legacy formats without losing custom port', () {
    final qr = ConnectionQr.parse(
      'GESTCOURS|192.168.1.20:48999|123456|GC-TEST',
    );
    expect(qr.address, '192.168.1.20:48999');
    expect(qr.principalId, 'GC-TEST');
    expect(qr.code, '123456');
    expect(ConnectionQr.parse('GESTCOURS|192.168.1.20|123456').principalId, '');
    expect(
      ConnectionQr.parse('ECOLEPRO|192.168.1.20|48999|Teacher|123456').address,
      '192.168.1.20:48999',
    );
  });
  test('QR rejects unrelated codes, URLs and malformed access codes', () {
    for (final raw in [
      'https://example.com',
      'GESTCOURS|a/b|123456',
      'GESTCOURS|a?x=y|123456',
      'GESTCOURS|x@y|123456',
      'GESTCOURS|192.168.1.20|12345',
      'GESTCOURS|192.168.1.20:99999|123456',
      'GESTCOURS|host|123456|abc def',
    ]) {
      expect(() => ConnectionQr.parse(raw), throwsFormatException, reason: raw);
    }
  });
  test(
    'pair pending, refusal, acceptance and QR Principal identity are enforced',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var state = 'pending';
      var principal = 'GC-TEST';
      String? requested;
      final subscription = server.listen((r) async {
        requested = r.uri.queryParameters['principalId'];
        r.response.headers.contentType = ContentType.json;
        r.response.write(
          jsonEncode({
            'ok': true,
            'protocolVersion': 6,
            'teacher': 'Teacher',
            'port': server.port,
            'principalId': principal,
            'deviceAuthorized': state == 'approved',
            'deviceStatus': state,
          }),
        );
        await r.response.close();
      });
      Future<PrincipalConfig> pair() => const PrincipalApi().pairAddress(
        '127.0.0.1:${server.port}',
        '123456',
        deviceId: 'PHONE-TEST',
        expectedPrincipalId: 'GC-TEST',
      );
      try {
        await expectLater(
          pair(),
          throwsA(isA<PrincipalApprovalPendingException>()),
        );
        expect(requested, 'GC-TEST');
        state = 'refused';
        await expectLater(pair(), throwsA(isA<PrincipalApiException>()));
        state = 'approved';
        expect((await pair()).principalId, 'GC-TEST');
        principal = 'GC-WRONG';
        await expectLater(pair(), throwsA(isA<PrincipalApiException>()));
      } finally {
        await subscription.cancel();
        await server.close(force: true);
        HttpOverrides.global = previousOverrides;
      }
    },
  );
  test('everyday errors never show a URL, SQL command or exception name', () {
    for (final value in [
      'DatabaseException sql PRAGMA busy_timeout',
      'SocketException GET http://x/?code=123456',
      'FormatException unexpected token',
      'StateError fake',
    ]) {
      final message = userMessage(value);
      expect(message, isNot(contains('Exception')));
      expect(message, isNot(contains('123456')));
      expect(message, isNot(contains('PRAGMA')));
      expect(message, isNot(contains('http://')));
    }
  });
  testWidgets('followup fits a small screen and reset asks before archiving', (
    tester,
  ) async {
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
  Future<int> resetFollowup() async {
    resetCalls++;
    return 1;
  }
}
