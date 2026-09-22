import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';

class LocalStore {
  static const _configKey = 'principal_config_v1';
  static const _snapshotKey = 'school_snapshot_v1';
  static const _legacyQueueKey = 'teacher_event_queue_v1';
  static const _eventsKey = 'teacher_events_v2';
  static const _deviceKey = 'mobile_device_id_v1';
  static const _syncLogKey = 'sync_log_v1';
  // Every instance shares this lock: updating the queue cannot erase concurrent additions.
  static Future<void> _writes = Future<void>.value();
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
  Future<void> _put(SharedPreferences p, String key, String value) async {
    if (!await p.setString(key, value)) {
      throw StateError('Enregistrement local impossible. Vérifiez le stockage du téléphone.');
    }
  }
  List<TeacherEvent> _readEvents(SharedPreferences p) {
    final raw = p.getString(_eventsKey) ?? p.getString(_legacyQueueKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    final list = decoded is Map ? decoded['events'] : decoded;
    if (list is! List || list.any((e) => e is! Map)) {
      throw const FormatException('Le stockage des saisies est illisible. Il a été conservé sans remplacement.');
    }
    return list.map((e) => TeacherEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }
  Future<void> _writeEvents(SharedPreferences p, List<TeacherEvent> events) =>
      _put(p, _eventsKey, jsonEncode({'version': 2, 'events': events.map((e) => e.toLocalJson()).toList()}));
  Future<void> saveConfig(PrincipalConfig config) => _locked(() async {
    final p = await _prefs;
    if (_readEvents(p).any((e) => e.teacher != config.teacher)) {
      throw StateError('Ce téléphone contient les saisies d’un autre professeur. Utilisez le professeur associé.');
    }
    final previous = p.getString(_configKey);
    if (previous != null) {
      final old = PrincipalConfig.fromJson(Map<String, dynamic>.from(jsonDecode(previous)));
      if (old.teacher != config.teacher && _readEvents(p).isNotEmpty) {
        throw StateError('Ce téléphone contient les saisies de ${old.teacher}. Conservez leur sauvegarde avant de changer de professeur.');
      }
    }
    await _put(p, _configKey, jsonEncode(config.toJson()));
  });
  Future<PrincipalConfig?> loadConfig() async {
    final raw = (await _prefs).getString(_configKey);
    return raw == null ? null : PrincipalConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }
  Future<void> clearConfig() => _locked(() async {
    final p = await _prefs;
    if (_readEvents(p).any((e) => e.status == 'pending' || e.status == 'received' || e.status == 'error')) {
      throw StateError('Des saisies attendent encore leur transmission ou validation.');
    }
    await p.remove(_configKey);
  });
  Future<void> saveSnapshot(SyncSnapshot snapshot) => _locked(() async =>
      _put(await _prefs, _snapshotKey, jsonEncode(snapshot.toJson())));
  Future<SyncSnapshot?> loadSnapshot() async {
    final raw = (await _prefs).getString(_snapshotKey);
    return raw == null ? null : SyncSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }
  Future<List<TeacherEvent>> loadAllEvents() => _locked(() async => _readEvents(await _prefs));
  Future<List<TeacherEvent>> loadQueue() async =>
      (await loadAllEvents()).where((e) => e.status == 'pending').toList();
  Future<void> enqueue(TeacherEvent event) => enqueueAll([event]);
  Future<void> enqueueAll(List<TeacherEvent> additions) => _locked(() async {
    final p = await _prefs;
    final events = _readEvents(p);
    final ids = events.map((e) => e.id).toSet();
    for (final event in additions) {
      if (ids.add(event.id)) events.add(event);
    }
    await _writeEvents(p, events);
  });
  Future<void> applyAcknowledgements(Set<String> ids, Map<String, String> errors) => _locked(() async {
    final p = await _prefs;
    final events = _readEvents(p).map((e) {
      if (e.status != 'pending') return e;
      if (ids.contains(e.id)) return e.copyWithStatus('received');
      if (errors.containsKey(e.id)) return e.copyWithStatus('error', note: errors[e.id]);
      return e;
    }).toList();
    await _writeEvents(p, events);
  });
  Future<void> applyReviews(List<Map<String, dynamic>> reviews) => _locked(() async {
    final p = await _prefs;
    final byId = {for (final r in reviews) r['id'].toString(): r};
    final events = _readEvents(p).map((e) {
      final r = byId[e.id];
      if (r == null || e.status == 'pending') return e;
      final status = r['status'] == 'pending' ? 'received' : r['status'].toString();
      if (!const ['received', 'accepted', 'refused'].contains(status)) return e;
      return e.copyWithStatus(status, note: (r['reviewNote'] ?? '').toString(), reviewedAt: (r['reviewedAt'] ?? '').toString());
    }).toList();
    await _writeEvents(p, events);
  });
  Future<void> retryEvent(String id) => _locked(() async {
    final p = await _prefs;
    await _writeEvents(p, _readEvents(p).map((e) => e.id == id && e.status == 'error' ? e.copyWithStatus('pending', note: '') : e).toList());
  });
  Future<String> getOrCreateDeviceId() => _locked(() async {
    final p = await _prefs;
    var value = p.getString(_deviceKey);
    if (value == null || value.isEmpty) {
      value = 'PHONE-${DateTime.now().microsecondsSinceEpoch}';
      await _put(p, _deviceKey, value);
    }
    return value;
  });
  Future<void> appendSyncLog(String message) => _locked(() async {
    final p = await _prefs;
    final items = p.getStringList(_syncLogKey) ?? <String>[];
    items.add('${DateTime.now().toIso8601String()}  $message');
    if (items.length > 500) items.removeRange(0, items.length - 500);
    await p.setStringList(_syncLogKey, items);
  });
  Future<List<String>> loadSyncLog() async => List<String>.from((await _prefs).getStringList(_syncLogKey) ?? const []);
  Future<void> clearSyncLog() => _locked(() async { await (await _prefs).remove(_syncLogKey); });
  Future<String> exportBundle() => _locked(() async {
    final p = await _prefs;
    return jsonEncode({'version': 2, 'config': p.getString(_configKey), 'snapshot': p.getString(_snapshotKey),
      'queue': jsonEncode(_readEvents(p).map((e) => e.toLocalJson()).toList()),
      'deviceId': p.getString(_deviceKey), 'syncLog': p.getStringList(_syncLogKey) ?? []});
  });
  Future<void> importBundle(String raw) => _locked(() async {
    final data = jsonDecode(raw);
    if (data is! Map || data['queue'] is! String) throw const FormatException('Sauvegarde invalide');
    final list = jsonDecode(data['queue'] as String);
    if (list is! List) throw const FormatException('Saisies de sauvegarde invalides');
    final imported = list.map((e) => TeacherEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    if (imported.any((e) => e.id.isEmpty || e.teacher.isEmpty || e.type.isEmpty)) {
      throw const FormatException('Une saisie de la sauvegarde est incomplète');
    }
    final p = await _prefs;
    PrincipalConfig? config;
    final configRaw = p.getString(_configKey) ?? data['config'];
    if (configRaw is String) {
      config = PrincipalConfig.fromJson(Map<String, dynamic>.from(jsonDecode(configRaw)));
    }
    final existing = _readEvents(p);
    final teachers = [...existing, ...imported].map((e) => e.teacher).toSet();
    if (config != null) teachers.add(config.teacher);
    if (teachers.length > 1) throw const FormatException('La sauvegarde appartient à un autre professeur. Aucune saisie importée.');
    if (data['snapshot'] is String) SyncSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(data['snapshot'] as String)));
    final all = {for (final e in _readEvents(p)) e.id: e};
    for (final e in imported) { all.putIfAbsent(e.id, () => e); }
    await _writeEvents(p, all.values.toList());
    for (final key in {'config': _configKey, 'snapshot': _snapshotKey}.entries) {
      if (p.getString(key.value) == null && data[key.key] is String) {
        await _put(p, key.value, data[key.key] as String);
      }
    }
  });
}
