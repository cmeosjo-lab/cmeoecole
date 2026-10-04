from pathlib import Path
m=Path('.')
if 'version: 0.6.2+16' in (m/'pubspec.yaml').read_text():
    raise SystemExit(0)
if 'version: 0.6.1+15' not in (m/'pubspec.yaml').read_text():
    raise SystemExit('Unexpected base version')
p=m/'lib/services/local_store.dart'
s=p.read_text()
needle='  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);'
insert='''  // Only a display acknowledgement; never modifies or deletes the original event.
  String _followupPrefix(String scope) =>
      'followup_hidden:${base64Url.encode(utf8.encode(scope))}:';

  Future<List<TeacherEvent>> loadFollowup({bool archived = false}) async {
    final d = await _db;
    final scope = await _scope(d);
    final comparison = archived
        ? "e.status != 'pending' AND m.value = e.status"
        : "(e.status = 'pending' OR m.value IS NULL OR m.value != e.status)";
    final rows = await d.rawQuery(
      "SELECT e.* FROM events e LEFT JOIN meta m ON m.key = ? || e.id "
      "WHERE e.scope = ? AND $comparison ORDER BY e.created_at DESC, e.id",
      [_followupPrefix(scope), scope],
    );
    return rows.map(_event).toList();
  }

  Future<int> resetFollowup() async {
    final d = await _db;
    final count = await d.transaction((tx) async {
      final scope = await _scope(tx);
      final rows = await tx.query('events', columns: ['id', 'status'],
          where: "scope = ? AND status != 'pending'", whereArgs: [scope]);
      for (final row in rows) {
        await _put(tx, '${_followupPrefix(scope)}${row['id']}', row['status'] as String);
      }
      return rows.length;
    });
    _changed();
    return count;
  }

'''
assert needle in s;s=s.replace(needle,insert+needle);p.write_text(s)
p=m/'lib/screens/home_screen.dart';s=p.read_text()
s=s.replace("import 'classes_screen.dart';", "import 'classes_screen.dart';\nimport 'followup_screen.dart';\nimport '../services/user_message.dart';")
s=s.replace('final h = await widget.store.loadTransmissionHistory();', 'final h = await widget.store.loadFollowup();',1)
s=s.replace('localError = e.toString()', 'localError = userMessage(e)')
a=s.index('  String _label(');b=s.index('  Future<void> _backup()',a)
s=s[:a]+'''  Future<void> _history() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
      FollowupScreen(store: widget.store, snapshot: snapshot)));
    await _refresh();
  }

'''+s[b:]
s=s.replace("case 'log':\n                  await _log();\n",'')
s=s.replace("              const PopupMenuItem(value: 'log', child: Text('Diagnostic')),\n",'')
a=s.index('              ExpansionTile(');b=s.index('              const SizedBox(height: 30)',a)
s=s[:a]+s[b:]
s=s.replace('final error = localError ?? c.lastError;', 'final error = localError ?? (c.lastError == null ? null : userMessage(c.lastError!));')
s=s.replace("const Text('Décisions du Principal')", "const Text('Suivi des saisies')")
s=s.replace("'Sauvegarde impossible : $e'", "userMessage(e, fallback: 'La sauvegarde n’a pas pu être préparée.')")
s=s.replace("'Restauration annulée : $e'", "userMessage(e, fallback: 'Cette sauvegarde ne peut pas être restaurée. Les données actuelles sont conservées.')")
s=s.replace("'Adresse non modifiée : $e'", "userMessage(e, fallback: 'La connexion n’a pas été modifiée. Vérifiez les informations auprès du Principal.')")
s=s.replace('Text(e.toString())', 'Text(userMessage(e))')
s=s.replace("Text('Restaurer une sauvegarde V2.4')", "Text('Restaurer une sauvegarde')")
p.write_text(s)
p=m/'lib/main.dart';s=p.read_text();s=s.replace('Ne désinstallez pas l’application.\\n\\n$startupError','Ne désinstallez pas l’application. Contactez l’administration pour vous aider.');p.write_text(s)
p=m/'lib/services/safe_save.dart';s=p.read_text();s="import 'user_message.dart';\n"+s;s=s.replace("'Enregistrement impossible. Le formulaire reste ouvert. $e'", "userMessage(e, fallback: 'L’enregistrement n’a pas abouti. Vérifiez les champs puis réessayez. Le formulaire reste ouvert.')");p.write_text(s)
p=m/'lib/services/principal_api.dart';s=p.read_text()
s=s.replace('class PrincipalApi {', """class PrincipalApprovalPendingException extends PrincipalApiException {
  PrincipalApprovalPendingException() : super(
      'Demande envoyée. L’administration doit l’accepter sur le tableau de bord du Principal.');
}

class PrincipalApi {""")
s=s.replace("mobileVersion = '0.6.1'", "mobileVersion = '0.6.2'")
s=s.replace('    Duration? pairTimeout,\n', "    Duration? pairTimeout,\n    String expectedPrincipalId = '',\n")
s=s.replace("          'code': code,\n", "          'code': code,\n          if (expectedPrincipalId.isNotEmpty) 'principalId': expectedPrincipalId,\n",1)
s=s.replace("      if (authorized == false) {\n        throw PrincipalApiException(\n          'Cet appareil attend une autorisation ou est désactivé. Sur le Principal : Réseau enseignants > Appareils autorisés.',\n        );\n      }", """      if (expectedPrincipalId.isNotEmpty && data['principalId'] != expectedPrincipalId) {
        throw PrincipalApiException('Ce QR ne correspond pas à cet établissement.');
      }
      if (authorized == false) {
        if (data['deviceStatus'] == 'refused' || data['deviceStatus'] == 'disabled') {
          throw PrincipalApiException('Connexion refusée par l’administration.');
        }
        throw PrincipalApprovalPendingException();
      }""")
s=s.replace('    required String deviceId,\n  }) async {\n    final raw = rawHost.trim();', "    required String deviceId,\n    String expectedPrincipalId = '',\n  }) async {\n    final raw = rawHost.trim();")
s=s.replace('      pairTimeout: const Duration(seconds: 3),\n', '      pairTimeout: const Duration(seconds: 3),\n      expectedPrincipalId: expectedPrincipalId,\n')
p.write_text(s)
p=m/'lib/screens/setup_screen.dart';s=p.read_text()
s="import 'dart:async';\n"+s
s=s.replace("import '../services/platform_permissions.dart';", "import '../services/platform_permissions.dart';\nimport '../services/user_message.dart';\nimport '../models/connection_qr.dart';")
s=s.replace('  bool busy = false;', '  bool busy = false, waiting = false;\n  int attempt = 0;')
s=s.replace("'Recopiez l’adresse affichée dans GESTCOURS Principal, puis votre code professeur.'", "'Scannez votre QR affiché par le Principal, ou saisissez votre adresse et votre code.'",1)
a=s.index('  Future<void> connect()');b=s.index('  @override\n  void dispose()',a)
s=s[:a]+'''  void _cancelWait() {
    attempt++;
    setState(() { busy = false; waiting = false; status = 'Vous pouvez relancer la connexion.'; });
  }

  Future<void> connect({String expectedPrincipalId = ''}) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim(), enteredCode = code.text.trim();
    if (enteredHost.isEmpty || !RegExp(r'^\\d{6}$').hasMatch(enteredCode)) {
      setState(() => error = 'Scannez le QR ou renseignez l’adresse et le code professeur à 6 chiffres.');
      return;
    }
    final run = ++attempt;
    setState(() { busy = true; waiting = false; error = null; status = 'Connexion au Principal…'; });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!mounted || run != attempt) return;
      if (!permission.mayProceed) {
        setState(() { busy = false; error = 'Autorisez le réseau local pour vous connecter au Principal.'; });
        return;
      }
      final device = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (mounted && run == attempt) {
        try {
          final config = await widget.api.pairAddress(enteredHost, enteredCode,
            deviceId: device, expectedPrincipalId: expectedPrincipalId);
          if (!mounted || run != attempt) return;
          setState(() { waiting = false; status = 'Connexion acceptée. Récupération de vos classes…'; });
          final snapshot = await widget.api.sync(config, deviceId: device);
          if (!mounted || run != attempt) return;
          await widget.store.activateSession(config, snapshot);
          if (!mounted || run != attempt) return;
          widget.onConnected(config);
          return;
        } on PrincipalApprovalPendingException {
          if (!mounted || run != attempt) return;
          if (DateTime.now().isAfter(deadline)) {
            setState(() { busy = false; waiting = false;
              status = 'La demande reste sur le Principal. Relancez la connexion après son acceptation.'; });
            return;
          }
          setState(() { waiting = true; status = 'Demande envoyée. L’administration doit cliquer sur Accepter dans le tableau de bord du Principal.'; });
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } catch (e) {
      if (!mounted || run != attempt) return;
      setState(() { busy = false; waiting = false; error = userMessage(e); status = 'Connexion non établie.'; });
    }
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (result == null || !mounted) return;
    try {
      final qr = ConnectionQr.parse(result);
      host.text = qr.address;
      code.text = qr.code;
      await connect(expectedPrincipalId: qr.principalId);
    } catch (e) {
      if (mounted) setState(() => error = userMessage(e));
    }
  }

'''+s[b:]
s=s.replace('    host.dispose();', '    attempt++;\n    host.dispose();',1)
s=s.replace("'Même Wi-Fi ou réseau local • adresse + code mémorisés après la première connexion'", "'Votre iPhone ou téléphone et le Principal doivent être sur le même Wi-Fi.'")
needle='                      const SizedBox(height: 22),\n                      TextField('
s=s.replace(needle,"""                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: busy ? null : scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scanner le QR du Principal'),
                      ),
                      const SizedBox(height: 14),
                      const Text('Ou saisir la connexion manuellement'),
                      const SizedBox(height: 12),
                      TextField(""")
s=s.replace('onPressed: busy ? null : connect,', 'onPressed: busy ? null : () => connect(),')
a=s.index('                      OutlinedButton.icon(');b=s.index('                      const SizedBox(height: 14)',a)
s=s[:a]+'''                      if (waiting) OutlinedButton(
                        onPressed: _cancelWait, child: const Text('Annuler l’attente')),
'''+s[b:]
s=s.replace("'L’adresse à recopier est affichée dans Principal > Réseau enseignants. Le port et votre nom ne sont pas à saisir.'", "'Le QR est disponible sur le tableau de bord du Principal : Connexion par QR. Chaque professeur a son propre code.'")
s=s.replace('    body: MobileScanner(\n', "    body: MobileScanner(\n      errorBuilder: (context, error) => const Center(child: Padding(\n        padding: EdgeInsets.all(24), child: Text('La caméra n’est pas accessible. Autorisez-la dans les réglages, ou revenez à la connexion manuelle.'))),\n")
p.write_text(s)
p=m/'pubspec.yaml';p.write_text(p.read_text().replace('0.6.1+15','0.6.2+16'))
