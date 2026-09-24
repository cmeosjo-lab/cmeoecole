import 'dart:async';
import 'package:flutter/widgets.dart';
import 'local_store.dart';
import 'principal_api.dart';
import 'sync_service.dart';

/// Automatic attempts while the application is open; not a suspended-iOS background service.
class SyncCoordinator extends ChangeNotifier with WidgetsBindingObserver {
  final LocalStore store;
  final PrincipalApi api;
  Timer? _timer;
  StreamSubscription<void>? _queueChanges;
  Future<SyncResult?>? _flight;
  bool _active = true, _disposed = false, _again = false, _maintenance = false;
  int _failures = 0;
  bool busy = false;
  String? lastError;
  SyncResult? lastResult;
  SyncCoordinator(this.store, this.api);
  void start() {
    WidgetsBinding.instance.addObserver(this);
    _queueChanges = store.enqueued.listen((_) {
      _again = true;
      schedule(const Duration(seconds: 2));
    });
    schedule(const Duration(seconds: 1));
  }

  void schedule(Duration delay) {
    _timer?.cancel();
    if (_active && !_disposed && !_maintenance) {
      _timer = Timer(delay, synchronize);
    }
  }

  Future<SyncResult?> synchronize() {
    if (_flight != null) return _flight!;
    if (_maintenance || _disposed) return Future.value(null);
    final f = _run();
    _flight = f;
    return f;
  }

  Future<SyncResult?> _run() async {
    _timer?.cancel();
    busy = true;
    _again = false;
    if (!_disposed) notifyListeners();
    try {
      final config = await store.loadConfig();
      if (config == null) return null;
      final result = await SyncService(store, api).synchronize(config);
      lastResult = result;
      lastError = null;
      _failures = 0;
      return result;
    } catch (e) {
      lastError = e.toString();
      _failures++;
      try {
        await store.appendSyncLog('Synchronisation différée : $e');
      } catch (_) {
        /* Do not hide the original error. */
      }
      return null;
    } finally {
      busy = false;
      _flight = null;
      if (!_disposed) {
        notifyListeners();
        final retrySeconds = _failures == 0
            ? 90
            : (5 * (1 << (_failures > 5 ? 5 : _failures - 1)));
        schedule(Duration(seconds: _again ? 2 : retrySeconds));
      }
    }
  }

  Future<void> maintain(Future<void> Function() action) async {
    if (_maintenance) throw StateError('Une opération est déjà en cours.');
    _maintenance = true;
    _timer?.cancel();
    try {
      if (_flight != null) await _flight;
      busy = true;
      if (!_disposed) notifyListeners();
      await action();
    } finally {
      busy = false;
      _maintenance = false;
      if (!_disposed) {
        notifyListeners();
        schedule(const Duration(seconds: 1));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active) {
      schedule(const Duration(seconds: 1));
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _queueChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
