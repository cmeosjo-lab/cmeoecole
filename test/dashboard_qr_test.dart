import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/connection_qr.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/school_data.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/sync_coordinator.dart';
import 'package:ecole_gestion_prof_mobile/screens/home_screen.dart';
import 'package:ecole_gestion_prof_mobile/screens/setup_screen.dart';
import 'package:ecole_gestion_prof_mobile/screens/transmission_screen.dart';
const config = PrincipalConfig(host:'192.168.1.20',port:47831,teacher:'Test',code:'123456',principalId:'GC-TEST');
TeacherEvent event(String id) => TeacherEvent(id:id,type:'attendance',teacher:'Test',studentId:'S',classId:'C',createdAt:DateTime(2026,10,4),payload: const {'status':'Absence'});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); sqfliteFfiInit();
  late Directory dir; late LocalStore store;
  setUp(() async { dir = await Directory.systemTemp.createTemp('gestcours_reset'); store = LocalStore(factory:databaseFactoryFfiNoIsolate,databasePath:'${dir.path}/data.db',legacyValues:const {}); await store.activateSession(config); });
  tearDown(() async { await store.close(); await dir.delete(recursive:true); });
  test('reset hides sent work but does not change queue or records', () async {
    await store.enqueueMany([event('P'),event('R'),event('A'),event('F')]);
    await store.resolveQueue(acknowledgedIds:{'R','A'},rejectedReasons:{'F':'Observation'});
    await store.updateTransmissionStatuses({'A':{'status':'accepted'}});
    final original = (await store.loadTransmissionHistory()).map((e)=>e.toLocalJson()).toList();
    expect(await store.resetDashboardTracking(),3); expect(await store.loadDashboardHistory(),isEmpty);
    expect((await store.loadQueue()).single.id,'P');
    expect((await store.loadTransmissionHistory()).map((e)=>e.toLocalJson()).toList(),original);
    expect((await store.loadDashboardHistory(archived:true)).length,3);
    await store.updateTransmissionStatuses({'R':{'status':'refused','reviewNote':'À corriger'}});
    expect((await store.loadDashboardHistory()).single.id,'R'); expect((await store.loadDashboardHistory(archived:true)).length,2);
  });
  test('reset persists across reopening without changing device identity', () async {
    final id = await store.getOrCreateDeviceId();
    await store.enqueue(event('R')); await store.resolveQueue(acknowledgedIds:{'R'}); await store.resetDashboardTracking();
    await store.close(); store = LocalStore(factory:databaseFactoryFfiNoIsolate,databasePath:'${dir.path}/data.db',legacyValues:const {});
    expect(await store.getOrCreateDeviceId(),id); expect(await store.loadDashboardHistory(),isEmpty); expect((await store.loadTransmissionHistory()).length,1);
  });
  test('new work and new decisions are visible after reset', () async {
    await store.enqueue(event('old')); await store.resolveQueue(acknowledgedIds:{'old'}); await store.resetDashboardTracking();
    await store.enqueue(event('new')); await store.resolveQueue(acknowledgedIds:{'new'});
    expect((await store.loadDashboardHistory()).map((e)=>e.id),['new']);
    await store.updateTransmissionStatuses({'old':{'status':'accepted'}}); expect((await store.loadDashboardHistory()).length,2);
  });
  test('reset never affects another teacher scope', () async {
    await store.enqueue(event('old')); await store.resolveQueue(acknowledgedIds:{'old'}); await store.resetDashboardTracking();
    const other = PrincipalConfig(host:'192.168.1.20',port:47831,teacher:'Other',code:'234567',principalId:'GC-TEST');
    await store.activateSession(other); expect(await store.resetDashboardTracking(),0);
    await store.activateSession(config); expect((await store.loadTransmissionHistory()).length,1); expect(await store.loadDashboardHistory(),isEmpty);
  });
  test('backup retains archived work and pending work', () async {
    await store.enqueueMany([event('P'),event('R')]); await store.resolveQueue(acknowledgedIds:{'R'}); await store.resetDashboardTracking();
    final backup = jsonDecode(await store.exportBundle()) as Map;
    expect((backup['events'] as List).length,2); expect((backup['meta'] as List).any((m)=>m['key'].toString().startsWith('dashboard_hidden:')),isTrue);
  });
  test('new QR accepts the exact local host port code and principal identity', () {
    final qr = ConnectionQr.parse('{"app":"GESTCOURS","version":1,"host":"192.168.1.20","port":47832,"code":"123456","principalId":"GC-TEST"}');
    expect(qr.address,'192.168.1.20:47832'); expect(qr.code,'123456'); expect(qr.principalId,'GC-TEST');
  });
  test('old QR formats remain readable including their explicit port', () {
    expect(ConnectionQr.parse('ECOLEPRO|192.168.1.20|47832|Test|123456').address,'192.168.1.20:47832');
    expect(ConnectionQr.parse('GESTCOURS|192.168.1.20:47833|123456').address,'192.168.1.20:47833');
  });
  test('QR rejects public hosts arbitrary URLs credentials and invalid values', () {
    for(final raw in ['https://example.com','GESTCOURS|8.8.8.8|123456','GESTCOURS|me@192.168.1.2|123456','GESTCOURS|192.168.1.2:70000|123456','GESTCOURS|192.168.1.2|abc123','GESTCOURS|192.168.1.2/path|123456','{"app":"OTHER"}']) {
      expect(()=>ConnectionQr.parse(raw),throwsFormatException,reason:raw);
    }
  });
  Future<void> render(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize=const Size(360,640); tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(textScaler:const TextScaler.linear(1.2)),child:child!),home:widget)); await tester.pump();
  }
  testWidgets('new connection screen has a visible scanner and no technical panel', (tester) async {
    await render(tester,SetupScreen(store:store,api:const PrincipalApi(),onConnected:(_){})); await tester.pumpAndSettle();
    expect(find.text('Scanner le QR de connexion'),findsOneWidget); expect(find.text('Informations techniques'),findsNothing); expect(tester.takeException(),isNull);
  });
  testWidgets('tracking offers reset and archives without layout overflow', (tester) async {
    await render(tester,TransmissionScreen(store:store)); await tester.pumpAndSettle();
    expect(find.text('Remettre le suivi à zéro'),findsOneWidget); expect(find.text('Voir les saisies archivées'),findsOneWidget); expect(tester.takeException(),isNull);
    await tester.tap(find.text('Remettre le suivi à zéro')); await tester.pumpAndSettle(); expect(find.text('Annuler'),findsOneWidget); expect(tester.takeException(),isNull);
    await tester.tap(find.text('Annuler')); await tester.pumpAndSettle();
  });
  testWidgets('home does not show technical storage protocol or build details', (tester) async {
    final snapshot=SyncSnapshot.fromJson({'principalId':'GC-TEST','teacher':'Test','classes':[],'students':[]}); await store.saveSnapshot(snapshot);
    final coordinator=SyncCoordinator(store,const PrincipalApi());
    await render(tester,HomeScreen(config:config,store:store,api:const PrincipalApi(),coordinator:coordinator,onDisconnect:(){})); await tester.pumpAndSettle();
    expect(find.textContaining('SQLite'),findsNothing); expect(find.text('Informations techniques'),findsNothing); expect(tester.takeException(),isNull);
    await tester.pumpWidget(const SizedBox()); coordinator.dispose();
  });
}
