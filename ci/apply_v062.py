from pathlib import Path
b=Path('.')
if 'version: 0.6.2+16' in (b/'pubspec.yaml').read_text():
    raise SystemExit('Sources V0.6.2 déjà préparées')
if 'version: 0.6.1+15' not in (b/'pubspec.yaml').read_text():
    raise SystemExit('Base mobile inattendue ; arrêt sans modification')
p=b/'lib/services/local_store.dart';s=p.read_text();needle='  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);';assert needle in s
s=s.replace(needle,'''  /// A reset archives the current visible states, never the events themselves.
  /// A later review/status change becomes visible again automatically.
  Future<List<TeacherEvent>> loadFollowUpHistory({bool archived = false}) async {
    final d = await _db;
    final scope = await _scope(d);
    final hidden = archived ? 'EXISTS' : 'NOT EXISTS';
    final rows = await d.rawQuery("SELECT e.* FROM events e WHERE e.scope = ? AND e.status != 'pending' AND $hidden (SELECT 1 FROM meta m WHERE m.key = 'followup_hidden:' || e.id AND m.value = e.status || char(31) || e.review_note) ORDER BY e.created_at, e.id", [scope]);
    return rows.map(_event).toList();
  }

  Future<void> resetFollowUp() async {
    final d = await _db;
    await d.transaction((tx) async {
      final scope = await _scope(tx);
      final rows = await tx.query('events', where: "scope = ? AND status != 'pending'", whereArgs: [scope]);
      for (final row in rows) {
        await _put(tx, 'followup_hidden:${row['id']}', "${row['status']}\\u001f${row['review_note']}");
      }
    });
    _changed();
  }

'''+needle);p.write_text(s)
p=b/'lib/screens/home_screen.dart';s=p.read_text();s=s.replace("import 'classes_screen.dart';","import 'classes_screen.dart';\nimport 'followup_screen.dart';\nimport '../services/user_message.dart';")
s=s.replace('final h = await widget.store.loadTransmissionHistory();','final h = await widget.store.loadFollowUpHistory();')
a=s.index('  String _label(');z=s.index('  Future<void> _backup()',a)
s=s[:a]+'''  Future<void> _history() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FollowUpScreen(store: widget.store, snapshot: snapshot)));
    await _refresh();
  }

'''+s[z:]
s=s.replace("                case 'log':\n                  await _log();\n",'')
s=s.replace("              const PopupMenuItem(value: 'log', child: Text('Diagnostic')),\n",'')
a=s.index('              ExpansionTile(\n                title: const Text(\'Informations techniques\')');z=s.index('              const SizedBox(height: 30),',a)
s=s[:a]+s[z:]
s=s.replace("title: const Text('Décisions du Principal')","title: const Text('Suivi des saisies')")
s=s.replace('child: Text(error),','child: Text(userMessage(error)),')
s=s.replace("Text('Sauvegarde impossible : $e')","Text(userMessage(e))").replace("Text('Restauration annulée : $e')","Text(userMessage(e))").replace("Text('Adresse non modifiée : $e')","Text(userMessage(e))").replace('Text(e.toString())','Text(userMessage(e))')
s=s.replace("Restaurer une sauvegarde V2.4", "Restaurer une sauvegarde")
p.write_text(s)
p=b/'lib/services/principal_api.dart';s=p.read_text();anchor='class PrincipalApi {'
s=s.replace(anchor,'''class PairingPendingException extends PrincipalApiException {
  final String confirmationCode;
  PairingPendingException(this.confirmationCode)
      : super('Votre demande attend l’accord du responsable sur le tableau de bord du Principal.');
}

'''+anchor)
s=s.replace("mobileVersion = '0.6.1'","mobileVersion = '0.6.2'")
s=s.replace('    Duration? pairTimeout,','    Duration? pairTimeout,\n    String expectedPrincipalId = \'\',')
a=s.index('      if (authorized == false) {');z=s.index('      return PrincipalConfig(',a)
s=s[:a]+'''      if (expectedPrincipalId.isNotEmpty && data['principalId'] != expectedPrincipalId) {
        throw PrincipalApiException('Ce PC ne correspond pas à votre établissement.');
      }
      if (authorized == false) {
        final state = (data['deviceState'] ?? 'pending').toString();
        if (state == 'refused' || state == 'disabled') {
          throw PrincipalApiException('Cet appareil est refusé ou désactivé. Contactez le responsable de l’établissement.');
        }
        if (state != 'pending') {
          throw PrincipalApiException('La demande ne peut pas être enregistrée. Contactez le responsable.');
        }
        throw PairingPendingException((data['confirmationCode'] ?? '').toString());
      }
'''+s[z:]
s=s.replace('''    required String deviceId,
  }) async {
    final raw = rawHost.trim();''','''    required String deviceId,
    String expectedPrincipalId = '',
  }) async {
    final raw = rawHost.trim();''')
s=s.replace('      pairTimeout: const Duration(seconds: 3),','      pairTimeout: const Duration(seconds: 3),\n      expectedPrincipalId: expectedPrincipalId,')
p.write_text(s)
p=b/'lib/screens/setup_screen.dart';s=p.read_text();s="import 'dart:async';\n"+s
s=s.replace("import '../models/principal_config.dart';","import '../models/principal_config.dart';\nimport '../models/pairing_code.dart';\nimport '../services/user_message.dart';")
s=s.replace('class _SetupScreenState extends State<SetupScreen> {','class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {')
s=s.replace('  bool busy = false;','''  bool busy = false, waiting = false, _active = true;
  Timer? _poll;
  int _attempt = 0, _polls = 0;
  String _expectedPrincipalId = '', _pendingHost = '', _pendingCode = '', _pendingDevice = '';
''')
s=s.replace('    super.initState();\n    _loadPrevious();','    super.initState();\n    WidgetsBinding.instance.addObserver(this);\n    _loadPrevious();')
s=s.replace('  Future<void> connect() async {\n    FocusScope','  Future<void> connect() async {\n    if (busy) return;\n    final attempt = ++_attempt;\n    _polls = 0;\n    FocusScope')
a=s.index('    try {\n      final deviceId = await widget.store.getOrCreateDeviceId();');z=s.index('  @override\n  void dispose()',a)
s=s[:a]+'''    try {
      _pendingDevice = await widget.store.getOrCreateDeviceId();
      _pendingHost = enteredHost;
      _pendingCode = enteredCode;
      await _tryConnection(attempt);
    } catch (e) {
      if (mounted && attempt == _attempt) setState(() { busy = false; error = userMessage(e); });
    }
  }

  Future<void> _tryConnection(int attempt) async {
    if (!mounted || attempt != _attempt) return;
    try {
      final c = await widget.api.pairAddress(_pendingHost, _pendingCode,
        deviceId: _pendingDevice, expectedPrincipalId: _expectedPrincipalId);
      if (!mounted || attempt != _attempt) return;
      setState(() { waiting=false; status='Connexion acceptée. Chargement de vos classes…'; });
      final snapshot = await widget.api.sync(c, deviceId: _pendingDevice);
      if (!mounted || attempt != _attempt) return;
      await widget.store.activateSession(c, snapshot);
      if (!mounted || attempt != _attempt) return;
      widget.onConnected(c);
    } on PairingPendingException catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() { waiting = true; error=null;
        status='Demande envoyée. Le responsable doit l’accepter sur le tableau de bord du Principal.${e.confirmationCode.isEmpty?'':'\\nRepère à vérifier ensemble : ${e.confirmationCode}'}\\nLa connexion se poursuivra automatiquement.'; });
      if (++_polls >= 90) { _stopWaiting(); return; }
      _schedulePoll();
    } catch (e) {
      try { await widget.store.appendSyncLog('Connexion non établie : $e'); } catch (_) {}
      if (!mounted || attempt != _attempt) return;
      setState(() { busy=false;waiting=false;error=userMessage(e);status='Connexion non établie.'; });
    }
  }
  void _schedulePoll() {
    _poll?.cancel();
    if (_active && waiting && mounted) {
      final attempt=_attempt;
      _poll=Timer(const Duration(seconds:3),()=>_tryConnection(attempt));
    }
  }
  void _stopWaiting() {
    _poll?.cancel(); ++_attempt;
    if(mounted) setState(() {busy=false;waiting=false;status='L’attente est interrompue. Votre demande reste visible sur le Principal. Appuyez sur Se connecter après son acceptation.';});
  }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _active=state==AppLifecycleState.resumed;
    if(_active) { _schedulePoll(); } else { _poll?.cancel(); }
  }

  Future<void> scanQr() async {
    if (busy) return;
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (result == null || !mounted) return;
    try {
      final parsed = PairingCode.parse(result);
      host.text=parsed.address;code.text=parsed.code;_expectedPrincipalId=parsed.principalId;
    } catch (_) { setState(()=>error='Ce QR n’est pas un code de connexion GESTCOURS.'); return; }
    await connect();
  }

'''+s[z:]
s=s.replace('    host.dispose();','    _poll?.cancel(); ++_attempt;\n    WidgetsBinding.instance.removeObserver(this);\n    host.dispose();')
s=s.replace('                      const SizedBox(height: 22),','''                      const SizedBox(height: 22),
                      FilledButton.icon(onPressed: busy ? null : scanQr,
                        icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner le QR du Principal')),
                      const SizedBox(height: 10),
                      const Text('Sur le PC : Tableau de bord → QR de connexion. Ou saisissez l’adresse et votre code ci-dessous.'),
                      const SizedBox(height: 16),''')
s=s.replace('                        controller: host,','                        controller: host,\n                        onChanged: (_) => _expectedPrincipalId = \'\',')
a=s.index('                      OutlinedButton.icon(\n                        onPressed: busy ? null : scanQr,');z=s.index('                      const SizedBox(height: 14),',a)
s=s[:a]+'''                      if (waiting) OutlinedButton(onPressed: _stopWaiting, child: const Text('Arrêter l’attente')),
'''+s[z:]
s=s.replace('Le port et votre nom ne sont pas à saisir.', 'Ces informations seront mémorisées.')
p.write_text(s)
p=b/'lib/main.dart';s=p.read_text().replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart';")
s=s.replace("Ne désinstallez pas l’application.\\n\\n$startupError", "Ne désinstallez pas l’application. Contactez le responsable pour récupérer vos données.")
s=s.replace('''              child: SelectableText(
                'Les données locales''','''              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SelectableText(
                'Les données locales''')
s=s.replace("Contactez le responsable pour récupérer vos données.',\n              ),", "Contactez le responsable pour récupérer vos données.',\n              ), const SizedBox(height: 20), OutlinedButton(onPressed: () async { await Clipboard.setData(ClipboardData(text: startupError!)); }, child: const Text('Copier un rapport pour le responsable'))]),")
p.write_text(s)
p=b/'lib/services/safe_save.dart';s=p.read_text().replace("import 'package:flutter/material.dart';","import 'package:flutter/material.dart';\nimport 'user_message.dart';").replace('Le formulaire reste ouvert. $e','Le formulaire reste ouvert. ${userMessage(e)}');p.write_text(s)
p=b/'pubspec.yaml';p.write_text(p.read_text().replace('version: 0.6.1+15','version: 0.6.2+16'))
