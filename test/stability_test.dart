import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/school_data.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/sync_service.dart';

const config = PrincipalConfig(host: '192.168.1.10', port: 47831, teacher: 'PROF_TEST', code: '123456');
TeacherEvent event(int id, {String type = 'attendance', Map<String, dynamic>? payload}) => TeacherEvent(
  id: 'TEST-$id', type: type, teacher: 'PROF_TEST', studentId: 'ELEVE_TEST',
  classId: 'CLASSE_TEST', createdAt: DateTime(2026, 9, 22),
  payload: payload ?? {'date': '22/09/2026', 'status': 'Absence'},
);
SyncSnapshot snapshot() => SyncSnapshot.fromJson({'protocolVersion': 6, 'teacher': 'PROF_TEST',
  'supportedEventTypes': ['attendance', 'lesson_followup', 'quran_progress'], 'students': [], 'classes': []});

class FakeApi extends PrincipalApi {
  int calls = 0;
  int? failAt;
  Future<void> Function()? duringSend;
  List<String>? ackOnly;
  @override
  Future<SyncSnapshot> sync(PrincipalConfig c, {String deviceId = ''}) async => snapshot();
  @override
  Future<Map<String, dynamic>> sendEvents(PrincipalConfig c, List<TeacherEvent> events, {String deviceId = ''}) async {
    calls++;
    if (calls == failAt) throw PrincipalApiException('Coupure simulée');
    await duringSend?.call();
    final ids = ackOnly ?? events.map((e) => e.id).toList();
    return {'acknowledgedIds': ids, 'received': ids.length};
  }
  @override
  Future<List<Map<String, dynamic>>> eventStatuses(PrincipalConfig c, List<String> ids, {String deviceId = ''}) async =>
    ids.map((id) => {'id': id, 'status': 'pending'}).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('ancienne file migrée, identifiants et contenu conservés', () async {
    SharedPreferences.setMockInitialValues({'teacher_event_queue_v1': jsonEncode([event(1).toLocalJson()])});
    final store = LocalStore();
    await store.enqueue(event(2));
    expect((await store.loadQueue()).map((e) => e.id), ['TEST-1', 'TEST-2']);
    expect((await store.loadQueue()).first.payload['status'], 'Absence');
  });
  test('saisies simultanées et accusés ne perdent aucune donnée', () async {
    final store = LocalStore();
    await store.enqueue(event(1));
    await Future.wait([
      ...List.generate(60, (i) => LocalStore().enqueue(event(i + 2))),
      store.applyAcknowledgements({'TEST-1'}, {}),
    ]);
    expect((await store.loadAllEvents()).length, 61);
    expect((await store.loadQueue()).length, 60);
  });
  test('ajout pendant un envoi conservé pour la synchronisation suivante', () async {
    final store = LocalStore();
    await store.enqueue(event(1));
    final api = FakeApi()..duringSend = () => store.enqueue(event(2));
    await SyncService(store, api).synchronize(config);
    expect((await store.loadQueue()).single.id, 'TEST-2');
    expect((await store.loadAllEvents()).first.status, 'received');
  });
  test('251 saisies découpées en trois lots', () {
    final batches = SyncService.batches(List.generate(251, event));
    expect(batches.map((e) => e.length), [100, 100, 51]);
  });
  test('limite de taille calculée en octets UTF-8', () {
    final batches = SyncService.batches(List.generate(10, (i) => event(i, payload: {'note': 'é' * 100000})));
    for (final batch in batches) {
      final wire = jsonEncode({'protocolVersion': 6, 'events': batch.map((e) => e.toProtocolV6Json()).toList()});
      expect(utf8.encode(wire).length, lessThanOrEqualTo(512 * 1024));
    }
  });
  test('coupure après premier lot puis reprise sans retransmission du premier', () async {
    final store = LocalStore();
    await store.enqueueAll(List.generate(251, event));
    final api = FakeApi()..failAt = 2;
    final first = await SyncService(store, api).synchronize(config);
    expect(first.connected, false);
    expect(first.remaining, 151);
    api.failAt = null;
    final second = await SyncService(store, api).synchronize(config);
    expect(second.sent, 151);
    expect((await store.loadAllEvents()).length, 251);
    expect(await store.loadQueue(), isEmpty);
  });
  test('accusé partiel ne supprime ni non-confirmés ni événements étrangers', () async {
    final store = LocalStore();
    await store.enqueueAll([event(1), event(2)]);
    await SyncService(store, FakeApi()..ackOnly = ['TEST-1', 'INCONNU']).synchronize(config);
    expect((await store.loadQueue()).single.id, 'TEST-2');
  });
  test('validation et refus conservent la décision et le motif', () async {
    final store = LocalStore();
    await store.enqueueAll([event(1), event(2)]);
    await store.applyAcknowledgements({'TEST-1', 'TEST-2'}, {});
    await store.applyReviews([{'id':'TEST-1','status':'accepted'}, {'id':'TEST-2','status':'refused','reviewNote':'Date à corriger'}]);
    final all = await store.loadAllEvents();
    expect(all.map((e) => e.status), ['accepted', 'refused']);
    expect(all.last.reviewNote, 'Date à corriger');
  });
  test('stockage corrompu conservé sans remplacement', () async {
    SharedPreferences.setMockInitialValues({'teacher_event_queue_v1': '{cassé'});
    await expectLater(LocalStore().enqueue(event(1)), throwsFormatException);
    expect((await SharedPreferences.getInstance()).getString('teacher_event_queue_v1'), '{cassé');
  });
  test('import idempotent et sauvegarde incompatible refusée avant mutation', () async {
    final store = LocalStore();
    await store.saveConfig(config);
    await store.enqueue(event(1));
    final backup = await store.exportBundle();
    await store.importBundle(backup);
    expect((await store.loadAllEvents()).length, 1);
    final other = jsonDecode(backup) as Map<String, dynamic>;
    other['queue'] = jsonEncode([event(2).toLocalJson()..['teacher'] = 'AUTRE_PROF_TEST']);
    await expectLater(store.importBundle(jsonEncode(other)), throwsFormatException);
    expect((await store.loadAllEvents()).length, 1);
  });
  test('contrat V6 transmet sourate/versets et ancien suivi de leçon', () {
    final quran = event(1, type: 'quran_progress', payload: {'surah': 2, 'verseFrom': 1, 'verseTo': 7});
    expect(quran.toProtocolV6Json()['quranProgress'], quran.payload);
    final legacy = event(2, type: 'lessonFollowUp', payload: {'lessonId': 'LECON_TEST', 'status': 'a_revoir'});
    expect(legacy.toProtocolV6Json()['type'], 'lesson_followup');
    expect(legacy.toProtocolV6Json()['lessonFollowUp']['status'], 'a_revoir');
  });
}
