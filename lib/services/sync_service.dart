import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import 'local_store.dart';
import 'principal_api.dart';

class SyncResult {
  final bool connected;
  final int sent;
  final int received;
  final int rejected;
  final int duplicates;
  final int unsupported;
  final int remaining;
  final List<String> errors;
  final SyncSnapshot? snapshot;
  final String message;

  const SyncResult({
    required this.connected,
    required this.sent,
    required this.received,
    required this.rejected,
    required this.duplicates,
    required this.unsupported,
    required this.remaining,
    required this.errors,
    required this.snapshot,
    required this.message,
  });
}

class SyncService {
  static const int batchSize = 120;
  final LocalStore store;
  final PrincipalApi api;
  const SyncService(this.store, this.api);

  int _asInt(dynamic value) => int.tryParse((value ?? '0').toString()) ?? 0;

  List<String> _asErrors(dynamic value) {
    if (value is! List) return const [];
    return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }

  Map<String, String> _rejectedReasons(dynamic value) {
    final out = <String, String>{};
    if (value is! List) return out;
    for (final raw in value) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = (map['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      out[id] = (map['reason'] ?? 'Saisie refusée par le Principal').toString().trim();
    }
    return out;
  }

  Future<void> _refreshReviewedStatuses(PrincipalConfig config, String deviceId) async {
    final history = await store.loadTransmissionHistory();
    final ids = history
        .where((e) => e.status == 'received' || e.status == 'pending')
        .map((e) => e.id)
        .toList()
        .reversed
        .take(100)
        .toList();
    if (ids.isEmpty) return;
    final statuses = await api.eventStatuses(config, ids, deviceId: deviceId);
    if (statuses.isNotEmpty) await store.updateTransmissionStatuses(statuses);
  }

  Future<SyncResult> synchronize(PrincipalConfig config) async {
    final deviceId = await store.getOrCreateDeviceId();
    final online = await api.ping(config);
    final queue = await store.loadQueue();
    await store.appendSyncLog('Début synchronisation — file locale: ${queue.length} saisie(s).');
    if (!online) {
      await store.appendSyncLog('ÉCHEC — PC Principal indisponible. ${queue.length} saisie(s) conservée(s).');
      return SyncResult(
        connected: false,
        sent: 0,
        received: 0,
        rejected: 0,
        duplicates: 0,
        unsupported: queue.where((e) => !e.supportedByPrincipal).length,
        remaining: queue.length,
        errors: const [],
        snapshot: await store.loadSnapshot(),
        message: 'Principal indisponible. ${queue.length} saisie(s) conservée(s) sur le téléphone.',
      );
    }

    final sendable = queue.where((e) => e.supportedByPrincipal).toList();
    final unsupported = queue.length - sendable.length;
    var sent = 0;
    var received = 0;
    var rejected = 0;
    var duplicates = 0;
    final errors = <String>[];

    for (var start = 0; start < sendable.length; start += batchSize) {
      final end = (start + batchSize < sendable.length) ? start + batchSize : sendable.length;
      final batch = sendable.sublist(start, end);
      final response = await api.sendEvents(config, batch, deviceId: deviceId);
      received += _asInt(response['received']);
      rejected += _asInt(response['rejected']);
      duplicates += _asInt(response['duplicates']);
      errors.addAll(_asErrors(response['errors']));

      final acknowledged = <String>{
        if (response['acknowledgedIds'] is List)
          ...(response['acknowledgedIds'] as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty),
      };
      final rejectedReasons = _rejectedReasons(response['rejectedItems']);
      sent += acknowledged.length;
      final remaining = await store.resolveQueue(
        acknowledgedIds: acknowledged,
        rejectedReasons: rejectedReasons,
      );
      await store.appendSyncLog(
        'Lot ${start + 1}-$end/${sendable.length} — reçus: ${_asInt(response['received'])}, accusés: ${acknowledged.length}, rejetés: ${_asInt(response['rejected'])}, doublons: ${_asInt(response['duplicates'])}, restant local: $remaining${rejectedReasons.isEmpty ? '' : ' — refus: ${rejectedReasons.values.take(3).join(' | ')}'}',
      );
    }

    if (unsupported > 0) {
      await store.appendSyncLog('$unsupported saisie(s) locale(s) non reconnue(s) par cette version du protocole et conservée(s).');
    }

    await _refreshReviewedStatuses(config, deviceId);
    final snapshot = await api.sync(config, deviceId: deviceId);
    await store.saveSnapshot(snapshot);
    await store.appendSyncLog('Référentiel/classes reçus — ${snapshot.classes.length} classe(s), ${snapshot.students.length} élève(s), ${snapshot.references.lessons.length} leçon(s).');

    final remaining = (await store.loadQueue()).length;
    final parts = <String>[
      'Principal connecté.',
      if (sendable.isNotEmpty) '$received reçu(s), $sent accusé(s) par le serveur',
      if (rejected > 0) '$rejected refusé(s)',
      if (duplicates > 0) '$duplicates doublon(s)',
      if (unsupported > 0) '$unsupported saisie(s) non compatible(s)',
      '$remaining en attente.',
    ];
    if (errors.isNotEmpty) parts.add('Détail : ${errors.take(3).join(' | ')}');

    return SyncResult(
      connected: true,
      sent: sent,
      received: received,
      rejected: rejected,
      duplicates: duplicates,
      unsupported: unsupported,
      remaining: remaining,
      errors: errors,
      snapshot: snapshot,
      message: parts.join(' '),
    );
  }
}
