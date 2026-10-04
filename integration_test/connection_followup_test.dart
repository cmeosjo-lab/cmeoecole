import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/screens/setup_screen.dart';

void main(){
 IntegrationTestWidgetsFlutterBinding.ensureInitialized();
 const cfg=PrincipalConfig(host:'127.0.0.1',port:47831,teacher:'Test',code:'123456',principalId:'TEST');
 testWidgets('native reset preserves pending records and receives later decisions',(tester)async{
  final path='${await getDatabasesPath()}/gestcours_followup_native_test.db';
  var store=LocalStore(databasePath:path,legacyValues:const{});
  TeacherEvent sample(String id)=>TeacherEvent(id:id,type:'attendance',teacher:'Test',studentId:'S',classId:'C',createdAt:DateTime(2026,10,4),payload:{'date':'04/10/2026','status':'Absence'});
  try{
   await store.activateSession(cfg);await store.enqueueMany([sample('pending'),sample('received')]);await store.resolveQueue(acknowledgedIds:{'received'});
   await store.resetFollowUp();expect(await store.loadFollowUpHistory(),isEmpty);expect((await store.loadQueue()).single.id,'pending');
   await store.close();store=LocalStore(databasePath:path,legacyValues:const{});expect(await store.loadFollowUpHistory(),isEmpty);
   await store.updateTransmissionStatuses({'received':{'status':'accepted'}});expect((await store.loadFollowUpHistory()).single.status,'accepted');expect((await store.loadQueue()).single.id,'pending');
  }finally{await store.close();await deleteDatabase(path);}
 });
 testWidgets('pairing waits for approval and opens classes only after approval',(tester)async{
  final path='${await getDatabasesPath()}/gestcours_pairing_native_test.db';
  final store=LocalStore(databasePath:path,legacyValues:const{});
  final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  var approved=false;var pairCount=0;var syncBeforeApproval=0;
  server.listen((r)async{
   r.response.headers.contentType=ContentType.json;
   if(r.uri.path=='/api/v1/pair'){
    pairCount++;r.response.write(jsonEncode({'ok':true,'protocolVersion':6,'teacher':'Test','principalId':'TEST','port':server.port,'deviceAuthorized':approved,'deviceState':approved?'approved':'pending','confirmationCode':'ABC123'}));
   }else if(r.uri.path=='/api/v1/sync'){
    if(!approved){syncBeforeApproval++;r.response.statusCode=403;}else{r.response.write(jsonEncode({'protocolVersion':6,'teacher':'Test','principalId':'TEST','schoolName':'École test','classes':[],'students':[]}));}
   }else {r.response.write('{}');}
   await r.response.close();
  });
  var connected=false;
  try{
   await tester.pumpWidget(MaterialApp(home:SetupScreen(store:store,api:const PrincipalApi(),onConnected:(_){connected=true;})));
   await tester.pumpAndSettle();
   final fields=find.byType(TextField);
   await tester.enterText(fields.at(0),'127.0.0.1:${server.port}');await tester.enterText(fields.at(1),'123456');
   await tester.ensureVisible(find.text('SE CONNECTER'));await tester.tap(find.text('SE CONNECTER'));await tester.pump(const Duration(seconds:2));
   expect(connected,false);expect(pairCount,greaterThanOrEqualTo(1));expect(syncBeforeApproval,0);expect(find.textContaining('ABC123'),findsOneWidget);
   approved=true;
   for(var i=0;i<12&&!connected;i++){await tester.pump(const Duration(seconds:1));}
   expect(connected,true);expect((await store.loadConfig())!.principalId,'TEST');expect(syncBeforeApproval,0);
   await tester.pumpWidget(const SizedBox());
  }finally{await server.close(force:true);await store.close();await deleteDatabase(path);}
 });
 testWidgets('refused device and wrong QR binding are not authorized',(tester)async{
  final server=await HttpServer.bind(InternetAddress.loopbackIPv4,0);
  server.listen((r)async{r.response.headers.contentType=ContentType.json;r.response.write(jsonEncode({'ok':true,'protocolVersion':6,'teacher':'Test','principalId':'TEST','port':server.port,'deviceAuthorized':false,'deviceState':'refused'}));await r.response.close();});
  try{
   const api=PrincipalApi();
   await expectLater(api.pairAddress('127.0.0.1:${server.port}','123456',deviceId:'PHONE-TEST'),throwsA(isA<PrincipalApiException>().having((e)=>e is PairingPendingException,'not pending',false)));
   await expectLater(api.pairAddress('127.0.0.1:${server.port}','123456',deviceId:'PHONE-TEST',expectedPrincipalId:'OTHER'),throwsA(isA<PrincipalApiException>()));
  }finally{await server.close(force:true);}
 });
}
