import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/sync_coordinator.dart';
import 'package:ecole_gestion_prof_mobile/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('reset requires confirmation and never removes pending work', (tester) async {
    const cfg = PrincipalConfig(host:'127.0.0.1', port:47831, teacher:'Synthetic', code:'123456', principalId:'TEST');
    final dir = await tester.runAsync(() => Directory.systemTemp.createTemp('gestcours_reset_ui'));
    final store = LocalStore(factory:databaseFactoryFfiNoIsolate, databasePath:'${dir!.path}/test.db', legacyValues:const {});
    const api=PrincipalApi();
    final coordinator=SyncCoordinator(store, api);
    tester.view.physicalSize=const Size(360,640);
    tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> drain() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.pumpAndSettle();
    }
    try {
      await tester.runAsync(() async {
        await store.activateSession(cfg);
        for(final id in ['pending','received']) {
          await store.enqueue(TeacherEvent(id:id,type:'attendance',teacher:cfg.teacher,studentId:'S',classId:'C',createdAt:DateTime(2026,10,4),payload:const {'status':'Absence'}));
        }
        await store.resolveQueue(acknowledgedIds:{'received'});
      });
      await tester.pumpWidget(MaterialApp(home:HomeScreen(config:cfg,store:store,api:api,coordinator:coordinator,onDisconnect:(){})));
      await drain();
      await tester.tap(find.text('Suivi des saisies'));
      await drain();
      expect(find.text('Remettre les compteurs à zéro'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.tap(find.text('Remettre les compteurs à zéro'));
      await tester.pumpAndSettle();
      expect(find.text('Remettre les compteurs à zéro ?'),findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async { expect((await store.loadDashboardHistory()).length,1); });
      await tester.tap(find.text('Remettre les compteurs à zéro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remettre à zéro'));
      await drain();
      await tester.runAsync(() async {
        expect(await store.loadDashboardHistory(),isEmpty);
        expect((await store.loadQueue()).single.id,'pending');
        expect((await store.loadTransmissionHistory()).single.id,'received');
      });
      expect(tester.takeException(),isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      coordinator.dispose();
      await tester.runAsync(() async { await store.close(); await dir.delete(recursive:true); });
    }
  });
}
