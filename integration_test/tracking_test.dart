import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Native reset keeps pending and restores a new decision', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/gestcours_native_reset_test.db';
    LocalStore make() => LocalStore(databasePath: path, legacyValues: const {});
    var store = make();
    try {
      const cfg = PrincipalConfig(
        host: '192.0.2.1',
        port: 47831,
        teacher: 'TEST',
        code: '123456',
        principalId: 'TEST',
      );
      await store.activateSession(cfg);
      for (final id in ['PENDING', 'RECEIVED', 'ACCEPTED']) {
        await store.enqueue(
          TeacherEvent(
            id: id,
            type: 'attendance',
            teacher: 'TEST',
            studentId: 'S',
            classId: 'C',
            createdAt: DateTime(2026, 10, 4),
            payload: const {},
          ),
        );
      }
      await store.resolveQueue(acknowledgedIds: {'RECEIVED', 'ACCEPTED'});
      await store.updateTransmissionStatuses({
        'ACCEPTED': {'status': 'accepted'},
      });
      await store.resetTransmissionDashboard();
      expect(await store.loadDashboardHistory(), isEmpty);
      expect((await store.loadQueue()).single.id, 'PENDING');
      await store.close();
      store = make();
      expect(await store.loadDashboardHistory(), isEmpty);
      await store.updateTransmissionStatuses({
        'RECEIVED': {'status': 'accepted'},
      });
      expect((await store.loadDashboardHistory()).single.id, 'RECEIVED');
      expect((await store.loadTransmissionHistory()).length, 2);
    } finally {
      await store.close();
      await deleteDatabase(path);
    }
  });
}
