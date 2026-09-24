import '../models/principal_config.dart';
import '../models/school_data.dart';
import 'local_store.dart';
import 'principal_api.dart';

class SyncResult {
  final bool connected;
  final int sent, received, rejected, duplicates, unsupported, remaining;
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
  static final _inFlight = Expando<Future<SyncResult>>();
  final LocalStore store;
  final PrincipalApi api;
  const SyncService(this.store, this.api);
  int _int(dynamic v) => int.tryParse('$v') ?? 0;

  Future<SyncResult> synchronize(PrincipalConfig config) {
    final current = _inFlight[store];
    if (current != null) return current;
    final future = _run(config);
    _inFlight[store] = future;
    return future;
  }

  Future<SyncResult> _run(PrincipalConfig initial) async {
    try {
      return await _synchronize(initial);
    } finally {
      _inFlight[store] = null;
    }
  }

  Future<SyncResult> _synchronize(PrincipalConfig initial) async {
    final deviceId = await store.getOrCreateDeviceId();
    var config = await store.loadConfig() ?? initial;
    // Read and authenticate the Principal before sending any local data.
    final snapshot = await api.sync(config, deviceId: deviceId);
    final remoteId = (snapshot.raw['principalId'] ?? '').toString();
    if (config.principalId.isNotEmpty && remoteId != config.principalId) {
      throw PrincipalApiException(
        'Ce PC n’est pas le Principal enregistré. Aucune saisie n’a été envoyée.',
      );
    }
    if (remoteId.isNotEmpty) config = config.withIdentity(remoteId);
    await store.activateSession(config, snapshot);
    final queue = await store.loadQueue(scope: config.scopeKey);
    final sendable = queue
        .where(
          (e) =>
              e.supportedByPrincipal &&
              e.teacher.trim().toLowerCase() ==
                  config.teacher.trim().toLowerCase(),
        )
        .toList();
    final unsupported = queue.length - sendable.length;
    var sent = 0, received = 0, rejected = 0, duplicates = 0;
    final errors = <String>[];
    for (var start = 0; start < sendable.length; start += batchSize) {
      final end = (start + batchSize < sendable.length)
          ? start + batchSize
          : sendable.length;
      final batch = sendable.sublist(start, end);
      final batchIds = batch.map((e) => e.id).toSet();
      final response = await api.sendEvents(config, batch, deviceId: deviceId);
      final ack = <String>{
        if (response['acknowledgedIds'] is List)
          ...(response['acknowledgedIds'] as List)
              .map((v) => v.toString())
              .where(batchIds.contains),
      };
      final refused = <String, String>{};
      if (response['rejectedItems'] is List) {
        for (final item in response['rejectedItems'] as List) {
          if (item is Map && batchIds.contains(item['id']?.toString())) {
            refused[item['id'].toString()] =
                (item['reason'] ?? 'Refus du Principal').toString();
          }
        }
      }
      await store.resolveQueue(
        acknowledgedIds: ack,
        rejectedReasons: refused,
        scope: config.scopeKey,
      );
      sent += ack.length;
      received += _int(response['received']);
      duplicates += _int(response['duplicates']);
      rejected += refused.length;
      await store.appendSyncLog(
        'Lot ${start + 1}–$end/${sendable.length} : ${ack.length} reçu(s), ${refused.length} refusé(s).',
      );
      if (ack.isEmpty && refused.isEmpty) {
        throw PrincipalApiException(
          'Le Principal n’a pas confirmé le lot. Les saisies sont conservées pour une nouvelle tentative.',
        );
      }
    }
    // All non-final receipts are queried in batches, not just the last 100.
    final history = await store.loadTransmissionHistory(scope: config.scopeKey);
    final ids = history
        .where((e) => e.status == 'received')
        .map((e) => e.id)
        .toList();
    for (var start = 0; start < ids.length; start += 80) {
      final end = start + 80 < ids.length ? start + 80 : ids.length;
      try {
        final selected = ids.sublist(start, end);
        final statuses = await api.eventStatuses(
          config,
          selected,
          deviceId: deviceId,
        );
        statuses.removeWhere((key, _) => !selected.contains(key));
        await store.updateTransmissionStatuses(
          statuses,
          scope: config.scopeKey,
        );
      } catch (_) {
        errors.add(
          'Les décisions du Principal seront actualisées à la prochaine synchronisation.',
        );
        break;
      }
    }
    final remaining = (await store.loadQueue(scope: config.scopeKey)).length;
    await store.markSuccessfulSync();
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
      message: remaining == 0
          ? 'Toutes les saisies ont été transmises.'
          : '$remaining saisie(s) conservées à envoyer.',
    );
  }
}
