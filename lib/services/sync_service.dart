import 'dart:convert';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import 'local_store.dart';
import 'principal_api.dart';

class SyncResult {
  final bool connected;
  final int sent, received, rejected, duplicates, unsupported, remaining;
  final List<String> errors;
  final SyncSnapshot? snapshot;
  final String message;
  const SyncResult({required this.connected, required this.sent, required this.received,
    required this.rejected, required this.duplicates, required this.unsupported,
    required this.remaining, required this.errors, required this.snapshot, required this.message});
}
class SyncService {
  final LocalStore store;
  final PrincipalApi api;
  const SyncService(this.store, this.api);
  static Future<void> _synchronizations = Future<void>.value();
  Future<SyncResult> synchronize(PrincipalConfig config) {
    final result = _synchronizations.then((_) => _synchronize(config));
    _synchronizations = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }
  static List<List<TeacherEvent>> batches(List<TeacherEvent> events) {
    final result = <List<TeacherEvent>>[];
    var batch = <TeacherEvent>[];
    var bytes = 128;
    for (final e in events) {
      final size = utf8.encode(jsonEncode(e.toProtocolV6Json())).length + 1;
      if (size > 512 * 1024) throw PrincipalApiException('Une saisie dépasse la taille autorisée. Elle est conservée dans le journal.');
      if (batch.isNotEmpty && (batch.length >= 100 || bytes + size > 512 * 1024)) {
        result.add(batch); batch = []; bytes = 128;
      }
      batch.add(e); bytes += size;
    }
    if (batch.isNotEmpty) result.add(batch);
    return result;
  }
  int _count(dynamic n) => int.tryParse('$n') ?? 0;
  Future<SyncResult> _synchronize(PrincipalConfig config) async {
    var snapshot = await store.loadSnapshot();
    var sent = 0, received = 0, rejected = 0, duplicates = 0, unsupported = 0;
    var connected = false;
    final errors = <String>[];
    try {
      final deviceId = await store.getOrCreateDeviceId();
      snapshot = await api.sync(config, deviceId: deviceId);
      connected = true;
      await store.saveSnapshot(snapshot);
      final queue = await store.loadQueue();
      final sendable = queue.where((e) => e.teacher == config.teacher && e.supportedByPrincipal && snapshot!.supportedEventTypes.contains(e.protocolType)).toList();
      unsupported = queue.length - sendable.length;
      for (final batch in batches(sendable)) {
        final response = await api.sendEvents(config, batch, deviceId: deviceId);
        final ids = batch.map((e) => e.id).toSet();
        final acknowledgements = response['acknowledgedIds'] is List
            ? (response['acknowledgedIds'] as List).map((e) => e.toString()).where(ids.contains).toSet() : <String>{};
        final eventErrors = <String, String>{};
        if (response['errorsById'] is Map) {
          for (final e in (response['errorsById'] as Map).entries) {
            if (ids.contains(e.key)) eventErrors[e.key.toString()] = e.value.toString();
          }
        }
        await store.applyAcknowledgements(acknowledgements, eventErrors);
        sent += acknowledgements.length;
        received += _count(response['received']);
        rejected += _count(response['rejected']);
        duplicates += _count(response['duplicates']);
        if (response['errors'] is List) errors.addAll((response['errors'] as List).map((e) => e.toString()));
        await store.appendSyncLog('Lot de ${batch.length} : ${acknowledgements.length} reçu(s), ${eventErrors.length} à corriger.');
        if (acknowledgements.isEmpty && eventErrors.isEmpty) {
          throw PrincipalApiException('Le Principal n’a pas confirmé ce lot. Il sera proposé à nouveau sans créer de doublon.');
        }
      }
      final waiting = (await store.loadAllEvents()).where((e) => e.teacher == config.teacher && e.status == 'received').map((e) => e.id).toList();
      for (var i = 0; i < waiting.length; i += 40) {
        final end = i + 40 < waiting.length ? i + 40 : waiting.length;
        await store.applyReviews(await api.eventStatuses(config, waiting.sublist(i, end), deviceId: deviceId));
      }
    } catch (e) {
      connected = false;
      errors.add(e.toString());
      await store.appendSyncLog('Synchronisation interrompue : $e');
    }
    final remaining = (await store.loadQueue()).length;
    final message = [connected ? 'Principal connecté.' : 'Synchronisation à reprendre.',
      '$sent saisie(s) reçue(s) par le Principal.', '$remaining à envoyer.',
      if (unsupported > 0) '$unsupported saisie(s) nécessitent le Principal V2.3 ou le professeur associé.',
      if (errors.isNotEmpty) errors.first].join(' ');
    return SyncResult(connected: connected, sent: sent, received: received, rejected: rejected,
      duplicates: duplicates, unsupported: unsupported, remaining: remaining,
      errors: errors, snapshot: snapshot, message: message);
  }
}
