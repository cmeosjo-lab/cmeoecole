import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/school_data.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/screens/class_evaluation_screen.dart';
import 'package:ecole_gestion_prof_mobile/screens/homework_screen.dart';
import 'package:ecole_gestion_prof_mobile/screens/class_lesson_screen.dart';
import 'package:ecole_gestion_prof_mobile/screens/quran_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const cfg = PrincipalConfig(
    host: '127.0.0.1',
    port: 47831,
    teacher: 'Test',
    code: '123456',
    principalId: 'TEST',
  );
  final snap = SyncSnapshot.fromJson({
    'protocolVersion': 6,
    'principalId': 'TEST',
    'teacher': 'Test',
    'schoolName': 'Test school',
    'classes': [
      {'id': 'C', 'name': 'Classe test', 'teacher': 'Test'},
    ],
    'students': List.generate(
      3,
      (i) => {
        'id': 'S$i',
        'name': 'Élève avec un nom très long $i',
        'firstName': 'Prénom de test',
        'classId': 'C',
      },
    ),
    'evaluationMax': 20,
    'referenceData': {
      'surahs': [
        {'id': '1', 'number': 1, 'name': 'Al-Fatiha', 'verseCount': 7},
      ],
      'lessons': [
        {'id': 'L', 'name': 'Leçon test', 'subject': 'Arabe', 'classId': 'C'},
      ],
    },
  });
  late LocalStore store;
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gestcours_layout');
    store = LocalStore(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: '${dir.path}/test.db',
      legacyValues: const {},
    );
    await store.activateSession(cfg, snap);
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  Future<void> render(
    WidgetTester tester,
    Widget child, {
    bool keyboard = false,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.2),
            viewInsets: EdgeInsets.only(bottom: keyboard ? 240 : 0),
          ),
          child: child!,
        ),
        home: child,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  testWidgets('class evaluation fits a small screen with keyboard', (
    tester,
  ) async {
    await render(
      tester,
      ClassEvaluationScreen(
        config: cfg,
        snapshot: snap,
        schoolClass: snap.classes.first,
        students: snap.students,
        store: store,
      ),
      keyboard: true,
    );
  });
  testWidgets('structured homework fits a small screen', (tester) async {
    await render(
      tester,
      HomeworkScreen(
        config: cfg,
        snapshot: snap,
        schoolClass: snap.classes.first,
        store: store,
      ),
    );
  });
  testWidgets('collective lesson form fits a small screen', (tester) async {
    await render(
      tester,
      ClassLessonScreen(
        config: cfg,
        snapshot: snap,
        schoolClass: snap.classes.first,
        students: snap.students,
        store: store,
      ),
    );
  });
  testWidgets('Quran form fits a small screen with keyboard', (tester) async {
    await render(
      tester,
      QuranScreen(
        config: cfg,
        snapshot: snap,
        student: snap.students.first,
        store: store,
      ),
      keyboard: true,
    );
  });
}
