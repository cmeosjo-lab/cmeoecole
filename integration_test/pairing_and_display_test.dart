import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/models/connection_qr.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/sync_coordinator.dart';
import 'package:ecole_gestion_prof_mobile/screens/transmission_history_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('QR HTTP pairing stays pending then accepts without changing identity', (tester) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var state = 'pending';
    var identity = 'GC-SYNTHETIC';
    var requestCount = 0;
    final observedIds = <String>{};
    final subscription = server.listen((request) async {
      expect(request.uri.path, '/api/v1/pair');
      expect(request.uri.queryParameters['code'], '123456');
      expect(request.uri.queryParameters['principalId'], 'GC-SYNTHETIC');
      observedIds.add(request.uri.queryParameters['deviceId'] ?? '');
      requestCount++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'ok': true, 'protocolVersion': 6, 'teacher': 'Test teacher',
        'port': server.port, 'principalId': identity,
        'deviceAuthorized': state == 'approved', 'deviceStatus': state,
      }));
      await request.response.close();
    });
    try {
      final qr = ConnectionQr.parse('GESTCOURS|127.0.0.1:${server.port}|123456|GC-SYNTHETIC');
      const api = PrincipalApi();
      Future<PrincipalConfig> pair() => api.pairAddress(qr.address, qr.code,
        deviceId: 'PHONE-TEST', expectedPrincipalId: qr.principalId);
      await expectLater(pair(), throwsA(isA<PairingPendingException>()));
      state = 'approved';
      final accepted = await pair();
      expect(accepted.principalId, 'GC-SYNTHETIC');
      expect(accepted.teacher, 'Test teacher');
      expect(accepted.port, server.port);
      state = 'refused';
      await expectLater(pair(), throwsA(isA<PrincipalApiException>().having(
        (e) => e.toString(), 'refusal', contains('refusé'))));
      state = 'disabled';
      await expectLater(pair(), throwsA(isA<PrincipalApiException>().having(
        (e) => e.toString(), 'disabled', contains('désactivé'))));
      state = 'approved'; identity = 'WRONG-PRINCIPAL';
      await expectLater(pair(), throwsA(isA<PrincipalApiException>().having(
        (e) => e.toString(), 'identity', contains('ne correspond plus'))));
      expect(requestCount, 5);
      expect(observedIds, {'PHONE-TEST'});
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  testWidgets('Tracking view fits small screen and resetting retains pending records', (tester) async {
    final path = '${await getDatabasesPath()}/gestcours_native_tracking_ui_test.db';
    final store = LocalStore(databasePath: path, legacyValues: const {});
    final coordinator = SyncCoordinator(store, const PrincipalApi());
    try {
      const config = PrincipalConfig(host: '192.0.2.1', port: 47831,
        teacher: 'Test teacher', code: '123456', principalId: 'GC-TEST');
      await store.activateSession(config);
      for (final id in ['PENDING', 'RECEIVED']) {
        await store.enqueue(TeacherEvent(id: id, type: 'attendance', teacher: config.teacher,
          studentId: 'TEST-STUDENT', classId: 'TEST-CLASS', createdAt: DateTime(2026, 10, 4),
          payload: const {'status': 'Absence'}));
      }
      await store.resolveQueue(acknowledgedIds: {'RECEIVED'});
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      for (final scale in [1.0, 1.3]) {
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: TransmissionHistoryScreen(store: store, coordinator: coordinator),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Remettre le suivi à zéro'), findsOneWidget);
      }
      await tester.tap(find.text('Remettre le suivi à zéro'));
      await tester.pumpAndSettle();
      expect(find.text('Remettre le suivi à zéro ?'), findsOneWidget);
      await tester.tap(find.text('Remettre à zéro'));
      await tester.pump();
      // Explicitly await the local operation; avoid starting any real network sync.
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 300)); });
      expect((await store.loadQueue()).single.id, 'PENDING');
      expect((await store.loadTransmissionHistory()).single.id, 'RECEIVED');
      expect(await store.loadDashboardHistory(), isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await store.close();
      await deleteDatabase(path);
    }
  });
}
