import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';

/// Critical records live in SQLite, not asynchronous preferences.
/// The old preference values are retained untouched after the one-time migration.
class LocalStore extends ChangeNotifier {
  final DatabaseFactory? factory;
  final String? databasePath;
  final Map<String, Object>? legacyValues;
  Future<Database>? _opening;
  final _enqueued = StreamController<void>.broadcast();
  Stream<void> get enqueued => _enqueued.stream;
  bool _closed = false;
  LocalStore({this.factory, this.databasePath, this.legacyValues});

  Future<Database> get _db => _opening ??= _open();
  void _changed() {
    if (!_closed) notifyListeners();
  }

  Future<String?> _get(DatabaseExecutor d, String key) async {
    final rows = await d.query(
      'meta',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _put(DatabaseExecutor d, String key, String value) async {
    await d.insert('meta', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  PrincipalConfig? _config(String? raw) =>
      raw == null ? null : PrincipalConfig.fromJson(_object(raw));
  Map<String, dynamic> _object(String raw) {
    final v = jsonDecode(raw);
    if (v is! Map) {
      throw const FormatException(
        'Objet JSON attendu. Données originales conservées.',
      );
    }
    return Map<String, dynamic>.from(v);
  }

  List<TeacherEvent> _decodeEvents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final v = jsonDecode(raw);
    if (v is! List) {
      throw const FormatException(
        'Liste des saisies illisible. Données originales conservées.',
      );
    }
    return v.map((item) {
      if (item is! Map) throw const FormatException('Saisie illisible.');
      final e = TeacherEvent.fromJson(Map<String, dynamic>.from(item));
      if (e.id.isEmpty || e.type.isEmpty) {
        throw const FormatException('Saisie sans identifiant ou type.');
      }
      return e;
    }).toList();
  }

  Future<Database> _open() async {
    final f = factory ?? databaseFactory;
    final path =
        databasePath ?? '${await f.getDatabasesPath()}/gestcours_v24.db';
    final d = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA synchronous = FULL');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE events (id TEXT PRIMARY KEY, scope TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, data TEXT NOT NULL, review_note TEXT NOT NULL DEFAULT "")',
          );
          await db.execute(
            'CREATE INDEX events_scope_status ON events(scope, status, created_at)',
          );
          await db.execute(
            'CREATE TABLE sync_log (id INTEGER PRIMARY KEY AUTOINCREMENT, stamp TEXT NOT NULL, message TEXT NOT NULL)',
          );
        },
      ),
    );
    try {
      final integrity = await d.rawQuery('PRAGMA quick_check');
      if (integrity.isEmpty || integrity.first.values.first != 'ok') {
        throw StateError(
          'La base locale est endommagée. Ne désinstallez pas GESTCOURS.',
        );
      }
      if (await _get(d, 'legacy_migrated') == null) {
        Map<String, Object> legacy;
        if (legacyValues != null) {
          legacy = legacyValues!;
        } else {
          final prefs = await SharedPreferences.getInstance();
          legacy = {
            for (final k in prefs.getKeys())
              if (prefs.get(k) != null) k: prefs.get(k)!,
          };
        }
        final cfgRaw = legacy['principal_config_v1'] as String?;
        final cfg = _config(cfgRaw);
        final snapshot = legacy['school_snapshot_v1'] as String?;
        if (snapshot != null) _object(snapshot);
        final queue = _decodeEvents(
          legacy['teacher_event_queue_v1'] as String?,
        );
        final history = _decodeEvents(
          legacy['teacher_event_transmission_v1'] as String?,
        );
        final scope = cfg?.scopeKey ?? 'legacy-unassigned';
        await d.transaction((tx) async {
          // Archive and marker are committed together with every migrated record.
          await _put(tx, 'legacy_backup', jsonEncode(legacy));
          if (cfgRaw != null) await _put(tx, 'config', cfgRaw);
          if (snapshot != null) await _put(tx, 'snapshot:$scope', snapshot);
          final device = legacy['mobile_device_id_v1'] as String?;
          if (device != null) await _put(tx, 'device', device);
          for (final e in history) {
            final status = e.status == 'pending' ? 'received' : e.status;
            await _insert(tx, e, scope, status);
          }
          for (final e in queue) {
            final old = await tx.query(
              'events',
              where: 'id = ?',
              whereArgs: [e.id],
            );
            if (old.isEmpty) await _insert(tx, e, scope, 'pending');
          }
          await _put(tx, 'legacy_migrated', '1');
        });
      }
      return d;
    } catch (_) {
      await d.close();
      rethrow;
    }
  }

  Future<void> _insert(
    DatabaseExecutor d,
    TeacherEvent e,
    String scope,
    String status,
  ) async {
    await d.insert('events', {
      'id': e.id,
      'scope': scope,
      'status': status,
      'created_at': e.createdAt.toIso8601String(),
      'data': jsonEncode(e.toLocalJson()),
      'review_note': (e.payload['_reviewNote'] ?? '').toString(),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  TeacherEvent _event(Map<String, Object?> row) =>
      TeacherEvent.fromJson(_object(row['data'] as String)).copyWithStatus(
        row['status'] as String,
        reviewNote: row['review_note'] as String,
      );
  Future<PrincipalConfig?> loadConfig() async =>
      _config(await _get(await _db, 'config'));
  Future<String> _scope(DatabaseExecutor d) async =>
      _config(await _get(d, 'config'))?.scopeKey ?? 'legacy-unassigned';

  Future<void> activateSession(
    PrincipalConfig cfg, [
    SyncSnapshot? snapshot,
  ]) async {
    final d = await _db;
    await d.transaction((tx) async {
      final old = _config(await _get(tx, 'config'));
      final oldScope = old?.scopeKey ?? 'legacy-unassigned';
      if (oldScope != cfg.scopeKey) {
        // Only an existing address/teacher can receive its first stable Principal ID.
        final sameLegacy =
            old != null &&
            old.principalId.isEmpty &&
            old.teacher.trim().toLowerCase() ==
                cfg.teacher.trim().toLowerCase() &&
            old.host.toLowerCase() == cfg.host.toLowerCase() &&
            old.port == cfg.port;
        if (sameLegacy) {
          await tx.update(
            'events',
            {'scope': cfg.scopeKey},
            where: 'scope = ?',
            whereArgs: [oldScope],
          );
          final oldSnapshot = await _get(tx, 'snapshot:$oldScope');
          if (oldSnapshot != null) {
            await _put(tx, 'snapshot:${cfg.scopeKey}', oldSnapshot);
          }
        } else {
          final pending =
              Sqflite.firstIntValue(
                await tx.rawQuery(
                  "SELECT COUNT(*) FROM events WHERE scope = ? AND status = 'pending'",
                  [oldScope],
                ),
              ) ??
              0;
          if (pending > 0) {
            throw StateError(
              '$pending saisie(s) non transmises : conservez la connexion précédente.',
            );
          }
        }
      }
      await _put(tx, 'config', jsonEncode(cfg.toJson()));
      if (snapshot != null) {
        if (snapshot.teacher.trim().toLowerCase() !=
            cfg.teacher.trim().toLowerCase()) {
          throw StateError(
            'Le référentiel reçu appartient à un autre professeur.',
          );
        }
        await _put(
          tx,
          'snapshot:${cfg.scopeKey}',
          jsonEncode(snapshot.toJson()),
        );
      }
    });
    _changed();
  }

  Future<void> saveConfig(PrincipalConfig c) => activateSession(c);
  Future<void> clearConfig() async {
    final d = await _db;
    await d.transaction((tx) async {
      final count =
          Sqflite.firstIntValue(
            await tx.rawQuery(
              "SELECT COUNT(*) FROM events WHERE scope = ? AND status = 'pending'",
              [await _scope(tx)],
            ),
          ) ??
          0;
      if (count > 0) {
        throw StateError(
          '$count saisie(s) restent à envoyer. Synchronisez avant de vous déconnecter.',
        );
      }
      await tx.delete('meta', where: 'key = ?', whereArgs: ['config']);
    });
    _changed();
  }

  Future<void> saveSnapshot(SyncSnapshot s) async {
    final cfg = await loadConfig();
    if (cfg == null) throw StateError('Connexion non configurée.');
    await activateSession(cfg, s);
  }

  Future<SyncSnapshot?> loadSnapshot() async {
    final d = await _db;
    final raw = await _get(d, 'snapshot:${await _scope(d)}');
    return raw == null ? null : SyncSnapshot.fromJson(_object(raw));
  }

  Future<List<TeacherEvent>> loadQueue({String? scope}) async {
    final d = await _db;
    final rows = await d.query(
      'events',
      where: "scope = ? AND status = 'pending'",
      whereArgs: [scope ?? await _scope(d)],
      orderBy: 'created_at, id',
    );
    return rows.map(_event).toList();
  }

  Future<List<TeacherEvent>> loadTransmissionHistory({String? scope}) async {
    final d = await _db;
    final rows = await d.query(
      'events',
      where: "scope = ? AND status != 'pending'",
      whereArgs: [scope ?? await _scope(d)],
      orderBy: 'created_at, id',
    );
    return rows.map(_event).toList();
  }

  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);
  Future<void> enqueueMany(List<TeacherEvent> events) async {
    final d = await _db;
    await d.transaction((tx) async {
      final cfg = _config(await _get(tx, 'config'));
      if (cfg == null) {
        throw StateError('Connectez cet appareil avant de saisir.');
      }
      for (final e in events) {
        if (e.teacher.trim().toLowerCase() !=
            cfg.teacher.trim().toLowerCase()) {
          throw StateError('Cette saisie appartient à un autre professeur.');
        }
        if (e.id.isEmpty || e.type.isEmpty) {
          throw const FormatException('Saisie incomplète.');
        }
        await _insert(tx, e, cfg.scopeKey, 'pending');
      }
    });
    _changed();
    if (!_closed) _enqueued.add(null);
  }

  Future<int> resolveQueue({
    required Set<String> acknowledgedIds,
    Map<String, String> rejectedReasons = const {},
    String? scope,
  }) async {
    final d = await _db;
    final result = await d.transaction((tx) async {
      final key = scope ?? await _scope(tx);
      // One transaction updates status without deleting the original record.
      for (final id in acknowledgedIds) {
        if (rejectedReasons.containsKey(id)) continue;
        await tx.update(
          'events',
          {'status': 'received'},
          where: "id = ? AND scope = ? AND status = 'pending'",
          whereArgs: [id, key],
        );
      }
      for (final e in rejectedReasons.entries) {
        await tx.update(
          'events',
          {'status': 'refused', 'review_note': e.value},
          where: "id = ? AND scope = ? AND status = 'pending'",
          whereArgs: [e.key, key],
        );
      }
      return Sqflite.firstIntValue(
            await tx.rawQuery(
              "SELECT COUNT(*) FROM events WHERE scope = ? AND status = 'pending'",
              [key],
            ),
          ) ??
          0;
    });
    _changed();
    return result;
  }

  Future<void> updateTransmissionStatuses(
    Map<String, Map<String, String>> updates, {
    String? scope,
  }) async {
    final d = await _db;
    await d.transaction((tx) async {
      final key = scope ?? await _scope(tx);
      for (final e in updates.entries) {
        var status = e.value['status'] ?? 'received';
        if (status == 'pending') status = 'received';
        if (!const {'received', 'accepted', 'refused'}.contains(status)) {
          continue;
        }
        await tx.update(
          'events',
          {'status': status, 'review_note': e.value['reviewNote'] ?? ''},
          where: "id = ? AND scope = ? AND status = 'received'",
          whereArgs: [e.key, key],
        );
      }
    });
    _changed();
  }

  Future<String> getOrCreateDeviceId() async {
    final d = await _db;
    return d.transaction((tx) async {
      final old = await _get(tx, 'device');
      if (old != null && old.isNotEmpty) return old;
      final id = 'PHONE-${const Uuid().v4()}';
      await _put(tx, 'device', id);
      return id;
    });
  }

  Future<void> markSuccessfulSync() async {
    final d = await _db;
    await _put(
      d,
      'last_success:${await _scope(d)}',
      DateTime.now().toIso8601String(),
    );
    _changed();
  }

  Future<DateTime?> lastSuccessfulSync() async {
    final d = await _db;
    final raw = await _get(d, 'last_success:${await _scope(d)}');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> appendSyncLog(String message) async {
    final d = await _db;
    await d.transaction((tx) async {
      await tx.insert('sync_log', {
        'stamp': DateTime.now().toIso8601String(),
        'message': message,
      });
      await tx.rawDelete(
        'DELETE FROM sync_log WHERE id NOT IN (SELECT id FROM sync_log ORDER BY id DESC LIMIT 300)',
      );
    });
  }

  Future<List<String>> loadSyncLog() async => (await (await _db).query(
    'sync_log',
    orderBy: 'id',
  )).map((r) => '${r['stamp']}  ${r['message']}').toList();
  Future<void> clearSyncLog() async {
    await (await _db).delete('sync_log');
  }

  Future<String> exportBundle() async {
    final d = await _db;
    return d.transaction(
      (tx) async => jsonEncode({
        'format': 'GESTCOURS',
        'version': 3,
        'meta': await tx.query('meta'),
        'events': await tx.query('events'),
        'logs': await tx.query('sync_log'),
      }),
    );
  }

  /// Restore merges records. It never deletes pending work and never clones a device ID.
  Future<void> importBundle(String raw) async {
    final bundle = _object(raw);
    if (bundle['format'] != 'GESTCOURS' ||
        bundle['version'] != 3 ||
        bundle['events'] is! List ||
        bundle['meta'] is! List) {
      throw const FormatException(
        'Utilisez une sauvegarde GESTCOURS V2.4. Les anciennes données sont migrées automatiquement lors de la mise à jour.',
      );
    }
    final rows = (bundle['events'] as List)
        .map((v) => Map<String, Object?>.from(v as Map))
        .toList();
    for (final row in rows) {
      final e = _event(row);
      if (e.id != row['id'] ||
          row['scope'] is! String ||
          !const {
            'pending',
            'received',
            'accepted',
            'refused',
          }.contains(row['status'])) {
        throw const FormatException('Sauvegarde des saisies invalide.');
      }
    }
    final d = await _db;
    await d.transaction((tx) async {
      for (final row in rows) {
        final existing = await tx.query(
          'events',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        if (existing.isNotEmpty) {
          if (existing.first['scope'] != row['scope'] ||
              existing.first['data'] != row['data']) {
            throw StateError(
              'Deux saisies différentes portent le même identifiant. Restauration annulée.',
            );
          }
          continue;
        }
        await tx.insert('events', row);
      }
      for (final item in bundle['meta'] as List) {
        final m = Map<String, dynamic>.from(item as Map);
        final key = m['key'] as String;
        final value = m['value'] as String;
        if (key == 'device' ||
            key == 'legacy_migrated' ||
            key == 'legacy_backup') {
          continue;
        }
        if (key == 'config') _config(value);
        if (key.startsWith('snapshot:')) _object(value);
        if (await _get(tx, key) == null) await _put(tx, key, value);
      }
    });
    _changed();
  }

  Future<void> close() async {
    if (_opening != null) {
      try {
        final d = await _opening!;
        await d.close();
      } catch (_) {
        /* Opening failure is already visible on the protection screen. */
      }
    }
    if (!_closed) {
      _closed = true;
      await _enqueued.close();
      super.dispose();
    }
  }
}
