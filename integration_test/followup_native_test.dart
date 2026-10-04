import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/screens/followup_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native reset archives receipts without deleting pending work and new decisions return', (tester) async {
    final path = '${await getDatabasesPath()}/gestcours_followup_test_${DateTime.now().microsecondsSinceEpoch}.db';
    var store = LocalStore(databasePath:path,legacyValues:const {});
    const config = PrincipalConfig(host:'192.0.2.1',port:47831,teacher:'Synthetic teacher',code:'123456',principalId:'GC-SYNTHETIC');
    TeacherEvent sample(String id)=>TeacherEvent(id:id,type:'attendance',teacher:config.teacher,studentId:'SYNTHETIC',classId:'SYNTHETIC',createdAt:DateTime(2026,1,1),payload:{'status':'Absence'});
    try {
      await store.activateSession(config);
      await store.enqueueMany([sample('PENDING'),sample('RECEIVED')]);
      await store.resolveQueue(acknowledgedIds:{'RECEIVED'});
      await tester.pumpWidget(MaterialApp(home:FollowupScreen(store:store)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset-followup')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remettre à zéro'));
      await tester.pumpAndSettle();
      expect((await store.loadFollowup()).single.id,'PENDING');
      expect((await store.loadFollowup(archived:true)).single.id,'RECEIVED');
      expect((await store.loadQueue()).single.id,'PENDING');
      await tester.pumpWidget(const SizedBox.shrink());
      await store.close();
      store=LocalStore(databasePath:path,legacyValues:const {});
      expect((await store.loadFollowup()).single.id,'PENDING');
      await store.updateTransmissionStatuses({'RECEIVED':{'status':'accepted'}});
      expect((await store.loadFollowup()).length,2);
      expect((await store.loadTransmissionHistory()).single.status,'accepted');
      expect(await store.loadFollowup(archived:true),isEmpty);
    } finally {
      await store.close();
      expect(path,contains('/gestcours_followup_test_'));
      await deleteDatabase(path);
    }
  });
}
