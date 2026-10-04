from pathlib import Path
p = Path('.')
def edit(f, old, new):
    t=(p/f).read_text()
    if old not in t:
        if new in t: return
        raise RuntimeError(f'Unexpected source: {f} {old[:60]}')
    (p/f).write_text(t.replace(old,new,1))

edit('pubspec.yaml','version: 0.6.1+15','version: 0.6.2+16')
edit('lib/services/principal_api.dart',"mobileVersion = '0.6.1'","mobileVersion = '0.6.2'")
edit('lib/services/principal_api.dart','class PrincipalApi {', '''class PrincipalApprovalPending implements Exception {
  final String teacher;
  const PrincipalApprovalPending(this.teacher);
  @override
  String toString() => 'Demande envoyée. Attendez l’accord du responsable sur le Principal.';
}

class PrincipalApi {''')
edit('lib/services/principal_api.dart',"if (authorized == false) {\n        throw PrincipalApiException(\n          'Cet appareil attend une autorisation ou est désactivé. Sur le Principal : Réseau enseignants > Appareils autorisés.',\n        );\n      }", """if (authorized == false) {
        if (data['deviceStatus'] == 'refused' || data['deviceStatus'] == 'disabled') {
          throw PrincipalApiException('Accès non autorisé par le responsable. Contactez l’établissement.');
        }
        throw PrincipalApprovalPending(teacher);
      }""")
edit('lib/services/local_store.dart','  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);', '''  Future<Set<String>> archivedDashboardIds() async {
    final d = await _db;
    final raw = await _get(d, 'dashboard_archived:${await _scope(d)}');
    if (raw == null) return <String>{};
    return (jsonDecode(raw) as List).cast<String>().toSet();
  }

  Future<List<TeacherEvent>> loadDashboardHistory() async {
    final hidden = await archivedDashboardIds();
    final history = await loadTransmissionHistory();
    return history.where((e) => !hidden.contains(e.id) ||
        (e.status != 'accepted' && e.status != 'refused')).toList();
  }

  /// Reset only visible completed counters; keep every original event and its status.
  Future<int> resetDashboardHistory() async {
    final d = await _db;
    final count = await d.transaction((tx) async {
      final scope = await _scope(tx);
      final key = 'dashboard_archived:$scope';
      final raw = await _get(tx, key);
      final hidden = raw == null ? <String>{} : (jsonDecode(raw) as List).cast<String>().toSet();
      final rows = await tx.query('events', columns: ['id'],
        where: "scope = ? AND status IN ('accepted', 'refused')", whereArgs: [scope]);
      final before = hidden.length;
      hidden.addAll(rows.map((r) => r['id'] as String));
      await _put(tx, key, jsonEncode(hidden.toList()..sort()));
      return hidden.length - before;
    });
    _changed();
    return count;
  }

  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);''')
h=p/'lib/screens/home_screen.dart'; t=h.read_text()
if "import 'entry_followup_screen.dart';" not in t:
    t=t.replace("import 'classes_screen.dart';", "import 'classes_screen.dart';\nimport 'entry_followup_screen.dart';\nimport '../services/user_messages.dart';")
    t=t.replace('final h = await widget.store.loadTransmissionHistory();','final h = await widget.store.loadDashboardHistory();',1)
    start=t.index('  String _label('); end=t.index('  Future<void> _backup()',start)
    t=t[:start]+'''  Future<void> _history() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) =>
      EntryFollowupScreen(store: widget.store, snapshot: snapshot)));
    await _refresh();
  }

'''+t[end:]
    t=t.replace("                case 'log':\n                  await _log();\n",'').replace("              const PopupMenuItem(value: 'log', child: Text('Diagnostic')),\n",'')
    start=t.index("              ExpansionTile(\n                title: const Text('Informations techniques')"); end=t.index('              const SizedBox(height: 30),',start)
    t=t[:start]+t[end:]
    t=t.replace("Text('Restaurer une sauvegarde V2.4')", "Text('Restaurer une sauvegarde')")
    t=t.replace('child: Text(error),', 'child: Text(localError != null ? userMessage(StateError(error)) : userMessage(PrincipalApiException(error))),')
    t=t.replace("Text('Sauvegarde impossible : $e')",'Text(userMessage(e))').replace("Text('Restauration annulée : $e')",'Text(userMessage(e))').replace("Text('Adresse non modifiée : $e')",'Text(userMessage(e))').replace('Text(e.toString())','Text(userMessage(e))')
    t=t.replace("title: const Text('Décisions du Principal')", "title: const Text('Suivi des saisies')")
    h.write_text(t)
edit('lib/main.dart',"'Les données locales n’ont pas pu être ouvertes. Aucune remise à zéro n’a été effectuée.\\n\\nNe désinstallez pas l’application.\\n\\n$startupError'", "'Les données locales n’ont pas pu être ouvertes. Aucune remise à zéro n’a été effectuée.\\n\\nNe désinstallez pas l’application. Contactez le responsable.'")

h=p/'lib/screens/setup_screen.dart'; t=h.read_text()
if "import '../services/pairing_code.dart';" not in t:
    t=t.replace("import '../services/platform_permissions.dart';", "import '../services/platform_permissions.dart';\nimport '../services/pairing_code.dart';\nimport '../services/user_messages.dart';")
    t=t.replace('  bool busy = false;', "  bool busy = false, waiting = false;\n  int _attempt = 0;\n  String _expectedPrincipal = '';\n")
    t=t.replace("'Recopiez l’adresse affichée dans GESTCOURS Principal, puis votre code professeur.';", "'Scannez votre QR affiché sur le Principal, ou saisissez votre adresse et votre code.';")
    start=t.index('  Future<void> connect() async {'); end=t.index('  @override\n  void dispose()',start)
    t=t[:start]+'''  void cancelConnection() {
    _attempt++;
    if (mounted) setState(() { busy = false; waiting = false; status = 'Connexion interrompue sur ce téléphone.'; });
  }

  Future<void> connect() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim(), enteredCode = code.text.trim();
    if (enteredHost.isEmpty || !RegExp(r'^\\d{6}$').hasMatch(enteredCode)) {
      setState(() => error = 'Saisissez l’adresse du Principal et le code à 6 chiffres, ou scannez votre QR.');
      return;
    }
    final attempt = ++_attempt;
    setState(() { busy = true; waiting = false; error = null; status = 'Connexion au Principal…'; });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!mounted || attempt != _attempt) return;
      if (!permission.mayProceed) throw PrincipalApiException(permission.message);
      final deviceId = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (mounted && attempt == _attempt) {
        try {
          final c = await widget.api.pairAddress(enteredHost, enteredCode, deviceId: deviceId);
          if (!mounted || attempt != _attempt) return;
          if (_expectedPrincipal.isNotEmpty && c.principalId != _expectedPrincipal) {
            throw PrincipalApiException('Ce QR ne correspond pas au Principal trouvé. Demandez un nouveau QR au responsable.');
          }
          setState(() { waiting = false; status = 'Connexion autorisée. Réception de vos classes…'; });
          final snapshot = await widget.api.sync(c, deviceId: deviceId);
          if (!mounted || attempt != _attempt) return;
          await widget.store.activateSession(c, snapshot);
          if (!mounted || attempt != _attempt) return;
          widget.onConnected(c);
          return;
        } on PrincipalApprovalPending catch (request) {
          if (!mounted || attempt != _attempt) return;
          setState(() { waiting = true; status = 'Demande envoyée pour ${request.teacher}. Le responsable doit l’accepter sur le tableau de bord du Principal.'; });
          if (DateTime.now().isAfter(deadline)) {
            throw PrincipalApiException('La demande attend toujours le responsable. Après son accord, appuyez sur Se connecter.');
          }
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } catch (e) {
      if (mounted && attempt == _attempt) setState(() { error = userMessage(e); status = 'Connexion non établie.'; });
    } finally {
      if (mounted && attempt == _attempt) setState(() { busy = false; waiting = false; });
    }
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (result == null || !mounted) return;
    try {
      final pairing = PairingCode.parse(result);
      host.text = pairing.address;
      code.text = pairing.code;
      _expectedPrincipal = pairing.principalId;
    } on FormatException {
      setState(() => error = 'QR non reconnu. Scannez le QR personnel affiché par le Principal.');
      return;
    }
    await connect();
  }

'''+t[end:]
    t=t.replace('    host.dispose();','    _attempt++;\n    host.dispose();')
    t=t.replace("label: const Text('Scanner un QR GESTCOURS (option)'),", "label: const Text('Scanner mon QR de connexion'),")
    needle='                      TextField(\n                        controller: host,'
    assert needle in t
    t=t.replace(needle,'''                      FilledButton.icon(onPressed: busy ? null : scanQr,
                        icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner mon QR de connexion')),
                      const SizedBox(height: 14),
                      const Text('Ou se connecter avec une adresse et un code'),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (_) => _expectedPrincipal = '',
                        controller: host,''')
    needle="""                      OutlinedButton.icon(
                        onPressed: busy ? null : scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scanner mon QR de connexion'),
                      ),"""
    assert needle in t
    t=t.replace(needle,"                      if (busy) OutlinedButton(onPressed: cancelConnection,\n                        child: const Text('Annuler l’attente')),")
    t=t.replace("'L’adresse à recopier est affichée dans Principal > Réseau enseignants. Le port et votre nom ne sont pas à saisir.'", "'Le responsable affiche votre QR depuis le tableau de bord du Principal. Il doit ensuite autoriser votre appareil.'")
    h.write_text(t)
print('V0.6.2: local archive only, QR parsing and approval waiting; no database deletion.')
