import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';

class LocalStore {
  static const _configKey = 'principal_config_v1';
  static const _snapshotKey = 'school_snapshot_v1';
  static const _queueKey = 'teacher_event_queue_v1';
  static const _transmissionKey = 'teacher_event_transmission_v1';
  static const _deviceKey = 'mobile_device_id_v1';
  static const _syncLogKey = 'sync_log_v1';

  Future<void> _queueSerial = Future<void>.value();

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<T> _queueExclusive<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queueSerial = _queueSerial.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> saveConfig(PrincipalConfig config) async {
    final p = await _prefs;
    await p.setString(_configKey, jsonEncode(config.toJson()));
  }

  Future<PrincipalConfig?> loadConfig() async {
    final p = await _prefs;
    final raw = p.getString(_configKey);
    if (raw == null) return null;
    return PrincipalConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  Future<void> clearConfig() async {
    final p = await _prefs;
    await p.remove(_configKey);
  }

  Future<void> saveSnapshot(SyncSnapshot snapshot) async {
    final p = await _prefs;
    await p.setString(_snapshotKey, jsonEncode(snapshot.toJson()));
  }

  Future<SyncSnapshot?> loadSnapshot() async {
    final p = await _prefs;
    final raw = p.getString(_snapshotKey);
    if (raw == null) return null;
    return SyncSnapshot.fromJson(Map<String, dynamic>.from(jsonDecode(raw)));
  }

  List<TeacherEvent> _decodeEvents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list.whereType<Map>().map((e) => TeacherEvent.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<List<TeacherEvent>> loadQueue() async {
    final p = await _prefs;
    return _decodeEvents(p.getString(_queueKey));
  }

  Future<List<TeacherEvent>> loadTransmissionHistory() async {
    final p = await _prefs;
    return _decodeEvents(p.getString(_transmissionKey));
  }

  Future<void> saveQueue(List<TeacherEvent> events) => _queueExclusive(() async {
        final p = await _prefs;
        await p.setString(_queueKey, jsonEncode(events.map((e) => e.toLocalJson()).toList()));
      });

  Future<void> enqueue(TeacherEvent event) => _queueExclusive(() async {
        final p = await _prefs;
        final events = _decodeEvents(p.getString(_queueKey));
        if (!events.any((e) => e.id == event.id)) events.add(event);
        await p.setString(_queueKey, jsonEncode(events.map((e) => e.toLocalJson()).toList()));
      });

  Future<int> resolveQueue({
    required Set<String> acknowledgedIds,
    Map<String, String> rejectedReasons = const {},
  }) =>
      _queueExclusive(() async {
        if (acknowledgedIds.isEmpty && rejectedReasons.isEmpty) {
          return (await loadQueue()).length;
        }
        final p = await _prefs;
        final current = _decodeEvents(p.getString(_queueKey));
        final history = _decodeEvents(p.getString(_transmissionKey));
        final byId = <String, TeacherEvent>{for (final e in history) e.id: e};
        final keep = <TeacherEvent>[];
        for (final e in current) {
          if (acknowledgedIds.contains(e.id)) {
            byId[e.id] = e.copyWithStatus('received');
          } else if (rejectedReasons.containsKey(e.id)) {
            byId[e.id] = e.copyWithStatus('refused', reviewNote: rejectedReasons[e.id]);
          } else {
            keep.add(e);
          }
        }
        final ordered = byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (ordered.length > 500) ordered.removeRange(0, ordered.length - 500);
        await p.setString(_queueKey, jsonEncode(keep.map((e) => e.toLocalJson()).toList()));
        await p.setString(_transmissionKey, jsonEncode(ordered.map((e) => e.toLocalJson()).toList()));
        return keep.length;
      });

  Future<void> updateTransmissionStatuses(Map<String, Map<String, String>> updates) => _queueExclusive(() async {
        if (updates.isEmpty) return;
        final p = await _prefs;
        final history = _decodeEvents(p.getString(_transmissionKey));
        var changed = false;
        final out = history.map((e) {
          final update = updates[e.id];
          if (update == null) return e;
          final status = (update['status'] ?? e.status).trim();
          final note = update['reviewNote'];
          changed = true;
          return e.copyWithStatus(status.isEmpty ? e.status : status, reviewNote: note);
        }).toList();
        if (changed) {
          await p.setString(_transmissionKey, jsonEncode(out.map((e) => e.toLocalJson()).toList()));
        }
      });

  Future<String> getOrCreateDeviceId() async {
    final p = await _prefs;
    var value = p.getString(_deviceKey);
    if (value == null || value.isEmpty) {
      value = 'PHONE-${DateTime.now().microsecondsSinceEpoch}';
      await p.setString(_deviceKey, value);
    }
    return value;
  }

  Future<void> appendSyncLog(String message) async {
    final p = await _prefs;
    final items = p.getStringList(_syncLogKey) ?? <String>[];
    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    items.add('$stamp  $message');
    if (items.length > 300) items.removeRange(0, items.length - 300);
    await p.setStringList(_syncLogKey, items);
  }

  Future<List<String>> loadSyncLog() async {
    final p = await _prefs;
    return List<String>.from(p.getStringList(_syncLogKey) ?? const <String>[]);
  }

  Future<void> clearSyncLog() async {
    final p = await _prefs;
    await p.remove(_syncLogKey);
  }

  Future<String> exportBundle() async {
    final p = await _prefs;
    return jsonEncode({
      'version': 2,
      'config': p.getString(_configKey),
      'snapshot': p.getString(_snapshotKey),
      'queue': p.getString(_queueKey),
      'transmissionHistory': p.getString(_transmissionKey),
      'deviceId': p.getString(_deviceKey),
      'syncLog': p.getStringList(_syncLogKey) ?? <String>[],
    });
  }

  Future<void> importBundle(String raw) => _queueExclusive(() async {
        final data = jsonDecode(raw);
        if (data is! Map) throw const FormatException('Sauvegarde invalide');
        final p = await _prefs;
        Future<void> putString(String key, dynamic value) async {
          final v = value?.toString() ?? '';
          if (v.isEmpty || v == 'null') {
            await p.remove(key);
          } else {
            await p.setString(key, v);
          }
        }
        await putString(_configKey, data['config']);
        await putString(_snapshotKey, data['snapshot']);
        await putString(_queueKey, data['queue']);
        await putString(_transmissionKey, data['transmissionHistory']);
        await putString(_deviceKey, data['deviceId']);
        if (data['syncLog'] is List) {
          await p.setStringList(_syncLogKey, (data['syncLog'] as List).map((e) => e.toString()).toList());
        }
      });
}
