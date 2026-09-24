import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ecole_gestion_prof_mobile/models/principal_config.dart';
import 'package:ecole_gestion_prof_mobile/models/school_data.dart';
import 'package:ecole_gestion_prof_mobile/models/teacher_event.dart';
import 'package:ecole_gestion_prof_mobile/services/local_store.dart';
import 'package:ecole_gestion_prof_mobile/services/principal_api.dart';
import 'package:ecole_gestion_prof_mobile/services/sync_service.dart';

const cfg = PrincipalConfig(
  host: '192.168.1.20',
  port: 47831,
  teacher: 'Test teacher',
  code: '123456',
  principalId: 'GC-TEST',
);
TeacherEvent event(
  String id, {
  String teacher = 'Test teacher',
  String type = 'attendance',
}) => TeacherEvent(
  id: id,
  type: type,
  teacher: teacher,
  studentId: 'S1',
  classId: 'C1',
  createdAt: DateTime(2026, 9, 1),
  payload: {'date': '01/09/2026', 'status': 'Absence'},
);
SyncSnapshot snapshot({
  String id = 'GC-TEST',
  String teacher = 'Test teacher',
}) => SyncSnapshot.fromJson({
  'protocolVersion': 6,
  'principalId': id,
  'teacher': teacher,
  'schoolName': 'Synthetic test school',
  'classes': [],
  'students': [],
});

class FakeApi extends PrincipalApi {
  int sends = 0, syncs = 0;
  final sizes = <int>[], statusSizes = <int>[];
  String remote = 'GC-TEST';
  Completer<void>? waitSync;
  Future<Map<String, dynamic>> Function(List<TeacherEvent>, int)? sendHook;
  @override
  Future<SyncSnapshot> sync(
    PrincipalConfig c, {
    required String deviceId,
  }) async {
    syncs++;
    if (waitSync != null) await waitSync!.future;
    return snapshot(id: remote);
  }

  @override
  Future<Map<String, dynamic>> sendEvents(
    PrincipalConfig c,
    List<TeacherEvent> events, {
    required String deviceId,
  }) async {
    sends++;
    sizes.add(events.length);
    if (sendHook != null) return sendHook!(events, sends);
    return {
      'received': events.length,
      'acknowledgedIds': events.map((e) => e.id).toList(),
    };
  }

  @override
  Future<Map<String, Map<String, String>>> eventStatuses(
    PrincipalConfig c,
    List<String> ids, {
    required String deviceId,
  }) async {
    statusSizes.add(ids.length);
    return {
      for (final id in ids) id: {'status': 'accepted', 'reviewNote': ''},
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late String path;
  LocalStore make({Map<String, Object> legacy = const {}}) => LocalStore(
    factory: databaseFactoryFfi,
    databasePath: path,
    legacyValues: legacy,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gestcours_test_');
    path = '${dir.path}/local.db';
    store = make();
    await store.activateSession(cfg, snapshot());
  });
  tearDown(() async {
    await store.close();
    await dir.delete(recursive: true);
  });
  test('pending records survive a database restart', () async {
    await store.enqueue(event('A'));
    await store.close();
    store = make();
    expect((await store.loadQueue()).single.id, 'A');
  });
  test('receipts never delete newly enqueued records', () async {
    await store.enqueue(event('A'));
    await store.enqueue(event('B'));
    await store.resolveQueue(acknowledgedIds: {'A'});
    expect((await store.loadQueue()).map((e) => e.id), ['B']);
    expect((await store.loadTransmissionHistory()).single.status, 'received');
  });
  test('explicit refusals retain their original data and reason', () async {
    await store.enqueue(event('A'));
    await store.resolveQueue(
      acknowledgedIds: {'A'},
      rejectedReasons: {'A': 'Invalid date'},
    );
    expect(await store.loadQueue(), isEmpty);
    final e = (await store.loadTransmissionHistory()).single;
    expect(e.status, 'refused');
    expect(e.payload['_reviewNote'], 'Invalid date');
    expect(e.payload['status'], 'Absence');
  });
  test('a failed grouped save rolls back the entire class', () async {
    await store.enqueue(event('EXISTS'));
    await expectLater(
      store.enqueueMany([event('NEW'), event('EXISTS')]),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.loadQueue()).map((e) => e.id), ['EXISTS']);
  });
  test('a foreign teacher cannot enqueue work', () async {
    await expectLater(
      store.enqueue(event('A', teacher: 'Other teacher')),
      throwsStateError,
    );
    expect(await store.loadQueue(), isEmpty);
  });
  test('logout is blocked while records are pending', () async {
    await store.enqueue(event('A'));
    await expectLater(store.clearConfig(), throwsStateError);
    expect((await store.loadConfig())!.principalId, 'GC-TEST');
  });
  test('switching Principal with pending records is blocked', () async {
    await store.enqueue(event('A'));
    const other = PrincipalConfig(
      host: '192.168.1.30',
      port: 47831,
      teacher: 'Test teacher',
      code: '123456',
      principalId: 'GC-OTHER',
    );
    await expectLater(store.activateSession(other), throwsStateError);
    expect((await store.loadConfig())!.principalId, cfg.principalId);
  });
  test('a new IP for the same stable Principal preserves the queue', () async {
    await store.enqueue(event('A'));
    const moved = PrincipalConfig(
      host: '192.168.1.55',
      port: 47831,
      teacher: 'Test teacher',
      code: '123456',
      principalId: 'GC-TEST',
    );
    await store.activateSession(moved);
    expect((await store.loadQueue()).single.id, 'A');
  });
  test('a mismatched teacher snapshot rolls back activation', () async {
    await expectLater(
      store.activateSession(cfg, snapshot(teacher: 'Other')),
      throwsStateError,
    );
    expect((await store.loadSnapshot())!.teacher, cfg.teacher);
  });
  test('terminal decisions cannot be downgraded by an old receipt', () async {
    await store.enqueue(event('A'));
    await store.resolveQueue(acknowledgedIds: {'A'});
    await store.updateTransmissionStatuses({
      'A': {'status': 'accepted'},
    });
    await store.updateTransmissionStatuses({
      'A': {'status': 'received'},
    });
    expect((await store.loadTransmissionHistory()).single.status, 'accepted');
  });
  test('large histories are not silently truncated at 500', () async {
    final events = List.generate(650, (i) => event('E$i'));
    await store.enqueueMany(events);
    await store.resolveQueue(acknowledgedIds: events.map((e) => e.id).toSet());
    expect((await store.loadTransmissionHistory()).length, 650);
  });
  test(
    'backup restore merges without deleting newly entered records',
    () async {
      await store.enqueue(event('A'));
      final backup = await store.exportBundle();
      await store.enqueue(event('B'));
      await store.importBundle(backup);
      expect((await store.loadQueue()).map((e) => e.id).toSet(), {'A', 'B'});
    },
  );
  test('conflicting backup IDs abort restoration atomically', () async {
    await store.enqueue(event('A'));
    final b = jsonDecode(await store.exportBundle()) as Map<String, dynamic>;
    final rows = b['events'] as List;
    final changed = Map<String, dynamic>.from(rows.first);
    final data = jsonDecode(changed['data'] as String) as Map<String, dynamic>;
    data['payload'] = {'different': true};
    changed['data'] = jsonEncode(data);
    b['events'] = [changed];
    await expectLater(store.importBundle(jsonEncode(b)), throwsStateError);
    expect((await store.loadQueue()).single.payload['status'], 'Absence');
  });
  test(
    'device identity is stable across restarts and not cloned by restore',
    () async {
      final id = await store.getOrCreateDeviceId();
      final b = jsonDecode(await store.exportBundle()) as Map<String, dynamic>;
      for (final row in b['meta'] as List) {
        if (row['key'] == 'device') row['value'] = 'FOREIGN-PHONE';
      }
      await store.importBundle(jsonEncode(b));
      await store.close();
      store = make();
      expect(await store.getOrCreateDeviceId(), id);
    },
  );
  test(
    'legacy preferences migrate exactly once without losing receipts',
    () async {
      await store.close();
      await File(path).delete();
      final oldCfg = PrincipalConfig(
        host: cfg.host,
        port: cfg.port,
        teacher: cfg.teacher,
        code: cfg.code,
      );
      final legacy = <String, Object>{
        'principal_config_v1': jsonEncode(oldCfg.toJson()),
        'school_snapshot_v1': jsonEncode(snapshot().toJson()),
        'teacher_event_queue_v1': jsonEncode([event('A').toLocalJson()]),
        'teacher_event_transmission_v1': jsonEncode([
          event('B').copyWithStatus('received').toLocalJson(),
        ]),
        'mobile_device_id_v1': 'OLD-PHONE',
      };
      store = make(legacy: legacy);
      expect((await store.loadQueue()).single.id, 'A');
      await store.activateSession(cfg, snapshot());
      expect((await store.loadQueue()).single.id, 'A');
      expect((await store.loadTransmissionHistory()).single.id, 'B');
      expect(await store.getOrCreateDeviceId(), 'OLD-PHONE');
      await store.close();
      store = make(legacy: legacy);
      expect((await store.loadQueue()).length, 1);
    },
  );
  test(
    'corrupt legacy JSON stops migration instead of emptying the queue',
    () async {
      await store.close();
      await File(path).delete();
      store = make(legacy: {'teacher_event_queue_v1': '[{broken'});
      await expectLater(store.loadQueue(), throwsFormatException);
      await store.close();
      store = make(
        legacy: {
          'principal_config_v1': jsonEncode(cfg.toJson()),
          'teacher_event_queue_v1': jsonEncode([
            event('RECOVERED').toLocalJson(),
          ]),
        },
      );
      expect((await store.loadQueue()).single.id, 'RECOVERED');
    },
  );
  test(
    '650 records are sent in bounded batches and all decisions fetched',
    () async {
      await store.enqueueMany(List.generate(650, (i) => event('E$i')));
      final api = FakeApi();
      final r = await SyncService(store, api).synchronize(cfg);
      expect(api.sizes, [120, 120, 120, 120, 120, 50]);
      expect(api.statusSizes, [80, 80, 80, 80, 80, 80, 80, 80, 10]);
      expect(r.remaining, 0);
      expect(
        (await store.loadTransmissionHistory()).every(
          (e) => e.status == 'accepted',
        ),
        isTrue,
      );
    },
  );
  test(
    'a disconnect after the first batch preserves every later record',
    () async {
      await store.enqueueMany(List.generate(301, (i) => event('E$i')));
      final api = FakeApi();
      api.sendHook = (events, n) async {
        if (n == 2) throw const SocketException('interrupted');
        return {'acknowledgedIds': events.map((e) => e.id).toList()};
      };
      await expectLater(
        SyncService(store, api).synchronize(cfg),
        throwsA(isA<SocketException>()),
      );
      expect((await store.loadQueue()).length, 181);
      expect((await store.loadTransmissionHistory()).length, 120);
    },
  );
  test('an empty reply is not treated as an acknowledgement', () async {
    await store.enqueue(event('A'));
    final api = FakeApi()..sendHook = ((events, n) async => {});
    await expectLater(
      SyncService(store, api).synchronize(cfg),
      throwsA(isA<PrincipalApiException>()),
    );
    expect((await store.loadQueue()).length, 1);
  });
  test('foreign acknowledgement IDs cannot consume unsent additions', () async {
    await store.enqueue(event('A'));
    final api = FakeApi();
    api.sendHook = (events, n) async {
      await store.enqueue(event('NEW'));
      return {
        'acknowledgedIds': ['A', 'NEW'],
      };
    };
    await SyncService(store, api).synchronize(cfg);
    expect((await store.loadQueue()).single.id, 'NEW');
  });
  test('a Principal identity mismatch sends nothing', () async {
    await store.enqueue(event('A'));
    final api = FakeApi()..remote = 'GC-FOREIGN';
    await expectLater(
      SyncService(store, api).synchronize(cfg),
      throwsA(isA<PrincipalApiException>()),
    );
    expect(api.sends, 0);
    expect((await store.loadQueue()).length, 1);
  });
  test('simultaneous synchronization calls share one operation', () async {
    await store.enqueue(event('A'));
    final api = FakeApi()..waitSync = Completer<void>();
    final service = SyncService(store, api);
    final first = service.synchronize(cfg);
    final second = service.synchronize(cfg);
    expect(identical(first, second), isTrue);
    api.waitSync!.complete();
    await Future.wait([first, second]);
    expect(api.sends, 1);
  });
  test('a transport refusal is retained and not retried forever', () async {
    await store.enqueue(event('A'));
    final api = FakeApi()
      ..sendHook = ((events, n) async => {
        'rejectedItems': [
          {'id': 'A', 'reason': 'Student moved'},
        ],
      });
    final r = await SyncService(store, api).synchronize(cfg);
    expect(r.rejected, 1);
    await SyncService(store, api).synchronize(cfg);
    expect(api.sends, 1);
    expect((await store.loadTransmissionHistory()).single.status, 'refused');
  });
  test('unsupported old event types remain recoverable locally', () async {
    await store.enqueue(event('A', type: 'old_unknown'));
    final api = FakeApi();
    final r = await SyncService(store, api).synchronize(cfg);
    expect(r.unsupported, 1);
    expect(r.remaining, 1);
    expect(api.sends, 0);
  });
  test(
    'JSON serialization preserves Unicode and structured Quran homework',
    () {
      final e = TeacherEvent.create(
        type: 'homework',
        teacher: 'Test teacher',
        studentId: '',
        classId: 'C1',
        payload: {
          'learnRanges': [
            {'surah': 'الفاتحة', 'from': 1, 'to': 7},
          ],
          'reviewRanges': [
            {'surah': 'الإخلاص', 'from': 1, 'to': 4},
          ],
        },
      );
      final wire = e.toProtocolV6Json();
      expect(
        (wire['homework'] as Map)['learnRanges'],
        e.payload['learnRanges'],
      );
      expect(TeacherEvent.fromJson(e.toLocalJson()).payload, e.payload);
    },
  );
}
