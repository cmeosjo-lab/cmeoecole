from pathlib import Path
p=Path('.')
if 'version: 0.6.2+16' in (p/'pubspec.yaml').read_text():
    raise SystemExit(0)
f=p/'pubspec.yaml'; f.write_text(f.read_text().replace('version: 0.6.1+15','version: 0.6.2+16'))
f=p/'lib/services/local_store.dart'; s=f.read_text(); mark='  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);'
assert mark in s
s=s.replace(mark,'''  /// A reset archives the display, never the sending queue or the original records.
  /// A new decision becomes visible when the event status changes after the reset.
  Future<List<TeacherEvent>> loadDashboardHistory() async {
    final d = await _db;
    return d.transaction((tx) async {
      final scope = await _scope(tx);
      final raw = await _get(tx, 'tracking_hidden:$scope');
      final hidden = raw == null ? <String, dynamic>{} : _object(raw);
      final rows = await tx.query('events',
        where: "scope = ? AND status != 'pending'", whereArgs: [scope], orderBy: 'created_at, id');
      return rows.where((r) => hidden[r['id']] != r['status']).map(_event).toList();
    });
  }
  Future<int> resetTransmissionDashboard() async {
    final d = await _db;
    final count = await d.transaction((tx) async {
      final scope = await _scope(tx);
      final rows = await tx.query('events', columns: ['id', 'status'],
        where: "scope = ? AND status != 'pending'", whereArgs: [scope]);
      await _put(tx, 'tracking_hidden:$scope', jsonEncode({
        for (final r in rows) r['id'] as String: r['status'],
      }));
      return rows.length;
    });
    _changed();
    return count;
  }

'''+mark)
f.write_text(s)
f=p/'lib/services/principal_api.dart'; s=f.read_text().replace("mobileVersion = '0.6.1'", "mobileVersion = '0.6.2'")
s=s.replace('class PrincipalApi {', '''class PairingPendingException extends PrincipalApiException {
  final PrincipalConfig config;
  PairingPendingException(this.config)
    : super('Demande envoyée. Attendez l’accord du responsable sur le Principal.');
}

class PrincipalApi {''')
s=s.replace('    Duration? pairTimeout,\n', "    Duration? pairTimeout,\n    String expectedPrincipalId = '',\n")
s=s.replace("          'code': code,\n          if (deviceId", "          'code': code,\n          if (expectedPrincipalId.isNotEmpty) 'principalId': expectedPrincipalId,\n          if (deviceId", 1)
start=s.index('      if (authorized == false) {'); end=s.index('\n    } on PrincipalApiException',start)
s=s[:start]+'''      final found = PrincipalConfig(host: host, port: returnedPort, teacher: teacher, code: code,
        principalId: (data['principalId'] ?? '').toString());
      if (expectedPrincipalId.isNotEmpty && found.principalId != expectedPrincipalId) {
        throw PrincipalApiException('Ce QR ne correspond plus à ce Principal. Demandez un nouveau QR code.');
      }
      if (authorized == false) {
        final state = (data['deviceStatus'] ?? 'pending').toString();
        if (state == 'refused') {
          throw PrincipalApiException('Le responsable a refusé cette demande. Contactez-le avant de réessayer.');
        }
        if (state == 'disabled') {
          throw PrincipalApiException('Cet appareil est désactivé. Demandez au responsable de le réactiver.');
        }
        throw PairingPendingException(found);
      }
      return found;'''+s[end:]
old='''    String rawCode, {
    required String deviceId,
  }) async {'''
assert old in s
s=s.replace(old,'''    String rawCode, {
    required String deviceId,
    String expectedPrincipalId = '',
  }) async {''')
s=s.replace('      pairTimeout: const Duration(seconds: 3),', "      pairTimeout: const Duration(seconds: 3),\n      expectedPrincipalId: expectedPrincipalId,")
f.write_text(s)
f=p/'lib/screens/home_screen.dart'; s=f.read_text().replace("import 'classes_screen.dart';", "import 'classes_screen.dart';\nimport 'transmission_history_screen.dart';")
s=s.replace('final h = await widget.store.loadTransmissionHistory();', 'final h = await widget.store.loadDashboardHistory();', 1)
start=s.index('  String _label(String s)'); end=s.index('\n  Future<void> _log()',start)
s=s[:start]+'''  Future<void> _history() async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
      TransmissionHistoryScreen(store: widget.store, coordinator: widget.coordinator, snapshot: snapshot)));
    await _refresh();
  }
'''+s[end:]
start=s.index("              const SizedBox(height: 16),\n              const Text(\n                'Envoi automatique après")
end=s.index('              const SizedBox(height: 30),',start)
s=s[:start]+s[end:]
s=s.replace('  PrincipalConfig? actualConfig;\n','').replace('      final config = await widget.store.loadConfig();\n','').replace('        actualConfig = config;\n','')
f.write_text(s)
f=p/'lib/screens/setup_screen.dart'; s="import 'dart:async';\n"+f.read_text()
s=s.replace("import '../models/principal_config.dart';", "import '../models/principal_config.dart';\nimport '../models/connection_qr.dart';")
s=s.replace('  bool busy = false;', "  bool busy = false, waiting = false;\n  int _attempt = 0;\n  String _qrPrincipalId = '';\n  Timer? _retry;\n  Completer<void>? _retryWait;")
start=s.index('  Future<void> connect() async {'); end=s.index('\n  @override\n  void dispose()',start)
s=s[:start]+'''  void _cancelWaiting() {
    _attempt++;
    _retry?.cancel();
    if (_retryWait != null && !_retryWait!.isCompleted) _retryWait!.complete();
    if (mounted) setState(() {
      busy = false; waiting = false;
      status = 'Vous pouvez relancer la connexion lorsque le responsable est prêt.';
    });
  }
  Future<void> connect() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim();
    final enteredCode = code.text.trim();
    if (enteredHost.isEmpty) {
      setState(() => error = 'Saisissez l’adresse du PC Principal ou scannez son QR code.');
      return;
    }
    if (!RegExp(r'^\\d{6}$').hasMatch(enteredCode)) {
      setState(() => error = 'Saisissez le code professeur à 6 chiffres.');
      return;
    }
    final attempt = ++_attempt;
    bool active() => mounted && attempt == _attempt;
    setState(() { busy = true; waiting = false; error = null; status = 'Connexion au Principal…'; });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!active()) return;
      if (!permission.mayProceed) throw PrincipalApiException(permission.message);
      final deviceId = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (active()) {
        try {
          final c = await widget.api.pairAddress(enteredHost, enteredCode,
            deviceId: deviceId, expectedPrincipalId: _qrPrincipalId);
          if (!active()) return;
          setState(() { waiting = false; status = 'Autorisation reçue. Chargement de vos classes…'; });
          final snapshot = await widget.api.sync(c, deviceId: deviceId);
          if (!active()) return;
          await widget.store.activateSession(c, snapshot);
          if (active()) widget.onConnected(c);
          return;
        } on PairingPendingException {
          if (!active()) return;
          if (DateTime.now().isAfter(deadline)) {
            throw PrincipalApiException('La demande reste en attente sur le Principal. Relancez la connexion après son acceptation.');
          }
          setState(() { waiting = true; status = 'Demande envoyée. Le responsable doit l’accepter sur le tableau de bord du Principal.'; });
          _retryWait = Completer<void>();
          _retry = Timer(const Duration(seconds: 4), () {
            if (!_retryWait!.isCompleted) _retryWait!.complete();
          });
          await _retryWait!.future;
        }
      }
    } catch (e) {
      if (active()) setState(() { error = e.toString(); status = 'Connexion non établie.'; });
    } finally {
      if (active()) setState(() { busy = false; waiting = false; });
    }
  }
  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (result == null || !mounted) return;
    try {
      final qr = ConnectionQr.parse(result);
      host.text = qr.address; code.text = qr.code; _qrPrincipalId = qr.principalId;
    } on FormatException catch (e) {
      setState(() => error = e.message); return;
    }
    await connect();
  }
'''+s[end:]
s=s.replace('    host.dispose();', '''    _attempt++;
    _retry?.cancel();
    if (_retryWait != null && !_retryWait!.isCompleted) _retryWait!.complete();
    host.dispose();''')
s=s.replace('                        controller: host,', "                        controller: host,\n                        onChanged: (_) => _qrPrincipalId = '',")
start=s.index("                      const SizedBox(height: 14),\n                      const Text(\n                        'L’adresse à recopier")
end=s.index('                    ],',start)
s=s[:start]+'''                      if (waiting) ...[
                        const SizedBox(height: 8),
                        TextButton(onPressed: _cancelWaiting, child: const Text('Arrêter l’attente')),
                      ],
'''+s[end:]
f.write_text(s)
f=p/'ci/android_startup_smoke.sh'; f.write_text(f.read_text().replace('V0_6_1','V0_6_2'))
