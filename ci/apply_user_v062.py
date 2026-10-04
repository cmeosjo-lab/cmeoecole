from pathlib import Path

p = Path('lib/services/local_store.dart')
s = p.read_text()
anchor = '  Future<void> enqueue(TeacherEvent event) => enqueueMany([event]);'
new = '''  // Archive the visible tracking only, never pending work or original events.
  // A new Principal decision makes the archived event visible again.
  Future<List<TeacherEvent>> loadDashboardHistory({bool archived = false}) async {
    final d = await _db;
    return d.transaction((tx) async {
      final scope = await _scope(tx);
      final raw = await _get(tx, 'dashboard_hidden:$scope');
      final hidden = raw == null ? <String, dynamic>{} : _object(raw);
      final rows = await tx.query('events',
        where: "scope = ? AND status != 'pending'", whereArgs: [scope],
        orderBy: 'created_at, id');
      return rows.where((row) {
        final marker = '${row['status']}|${row['review_note']}';
        final isHidden = hidden[row['id']] == marker;
        return archived ? isHidden : !isHidden;
      }).map(_event).toList();
    });
  }

  Future<int> resetDashboardTracking() async {
    final d = await _db;
    final count = await d.transaction((tx) async {
      final scope = await _scope(tx);
      final rows = await tx.query('events',
        columns: ['id', 'status', 'review_note'],
        where: "scope = ? AND status != 'pending'", whereArgs: [scope]);
      await _put(tx, 'dashboard_hidden:$scope', jsonEncode({
        for (final row in rows) row['id'] as String:
          '${row['status']}|${row['review_note']}',
      }));
      return rows.length;
    });
    _changed();
    return count;
  }

'''
if 'resetDashboardTracking' not in s:
    assert anchor in s
    s = s.replace(anchor, new + anchor, 1)
    p.write_text(s)

p = Path('lib/screens/home_screen.dart'); s = p.read_text()
if "import 'transmission_screen.dart';" not in s:
    s = s.replace("import 'classes_screen.dart';", "import 'classes_screen.dart';\nimport 'transmission_screen.dart';\nimport '../services/user_message.dart';")
    s = s.replace('final h = await widget.store.loadTransmissionHistory();', 'final h = await widget.store.loadDashboardHistory();', 1)
    start = s.index('  String _label('); end = s.index('  Future<void> _backup()', start)
    s = s[:start] + '''  Future<void> _history() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TransmissionScreen(store: widget.store, snapshot: snapshot)));
    await _refresh();
  }

''' + s[end:]
    s = s.replace("                case 'log':\n                  await _log();\n", '').replace("              const PopupMenuItem(value: 'log', child: Text('Diagnostic')),\n", '')
    start = s.index('              ExpansionTile(\n'); end = s.index('              const SizedBox(height: 30),', start)
    s = s[:start] + s[end:]
    s = s.replace('child: Text(error),', 'child: Text(userMessage(error)),').replace("'Restaurer une sauvegarde V2.4'", "'Restaurer une sauvegarde'")
    for old, new in [
        ("SnackBar(content: Text('Sauvegarde impossible : $e'))", "SnackBar(content: Text(userMessage(e, fallback: 'Sauvegarde impossible. Réessayez.')))"),
        ("SnackBar(content: Text('Restauration annulée : $e'))", "SnackBar(content: Text(userMessage(e, fallback: 'Restauration annulée. Les données sont conservées.')))"),
        ("SnackBar(content: Text('Adresse non modifiée : $e'))", "SnackBar(content: Text(userMessage(e, fallback: 'Adresse non modifiée. Réessayez.')))"),
        ('SnackBar(content: Text(e.toString()))', 'SnackBar(content: Text(userMessage(e)))'),
    ]: s = s.replace(old, new)
    p.write_text(s)

p = Path('lib/services/principal_api.dart'); s = p.read_text()
s = s.replace("mobileVersion = '0.6.1'", "mobileVersion = '0.6.2'")
if 'class PrincipalApprovalPending' not in s:
    s = s.replace('class PrincipalApi {', "class PrincipalApprovalPending extends PrincipalApiException {\n  PrincipalApprovalPending() : super('Demande envoyée. Le responsable doit autoriser cet appareil sur le tableau de bord du Principal.');\n}\n\nclass PrincipalApi {")
    s = s.replace('    Duration? pairTimeout,\n', "    Duration? pairTimeout,\n    String expectedPrincipalId = '',\n", 1)
    s = s.replace("      final authorized = data['deviceAuthorized'];", "      final authorized = data['deviceAuthorized'];\n      if (expectedPrincipalId.isNotEmpty && data['principalId'] != expectedPrincipalId) {\n        throw PrincipalApiException('Ce QR ne correspond plus au Principal. Demandez un nouveau QR code.');\n      }")
    start = s.index('      if (authorized == false) {'); end = s.index('      return PrincipalConfig(', start)
    s = s[:start] + '''      if (authorized == false) {
        if (data['deviceStatus'] == 'refused' || data['deviceStatus'] == 'disabled') {
          throw PrincipalApiException('Cet appareil n’est pas autorisé. Contactez le responsable de l’établissement.');
        }
        throw PrincipalApprovalPending();
      }
''' + s[end:]
    pos = s.index('  Future<PrincipalConfig> pairAddress(')
    part = s[pos:].replace('    required String deviceId,\n', "    required String deviceId,\n    String expectedPrincipalId = '',\n", 1).replace('      pairTimeout: const Duration(seconds: 3),', "      pairTimeout: const Duration(seconds: 3),\n      expectedPrincipalId: expectedPrincipalId,", 1)
    s = s[:pos] + part
    s = s.replace("'Le Principal répond, mais l’appairage a échoué (${r.statusCode}).'", "'Le Principal répond, mais la connexion n’a pas abouti. Réessayez.'")
    s = s.replace("'Synchronisation refusée (${r.statusCode})${detail.isEmpty ? '' : ' : $detail'}'", "'La synchronisation n’a pas abouti. Réessayez ou contactez le responsable.'")
    s = s.replace("'Transmission refusée (${r.statusCode})${detail.isEmpty ? '' : ' : $detail'}'", "'L’envoi n’a pas abouti. Vos saisies restent conservées. Réessayez.'")
    s = s.replace("'Version de protocole incompatible : Principal ${snapshot.protocolVersion}, mobile $supportedProtocol.'", "'Une mise à jour du Principal ou de l’application est nécessaire.'")
    s = s.replace("'Les décisions du Principal ne sont pas disponibles (${r.statusCode}).'", "'Les décisions du Principal ne sont pas encore disponibles. Réessayez plus tard.'")
p.write_text(s)
p = Path('lib/main.dart'); s = p.read_text().replace('Ne désinstallez pas l’application.\\n\\n$startupError', 'Ne désinstallez pas l’application. Contactez le responsable.'); p.write_text(s)
p = Path('pubspec.yaml'); s = p.read_text().replace('version: 0.6.1+15', 'version: 0.6.2+16'); p.write_text(s)
assert "rawQuery('PRAGMA busy_timeout = 5000')" in Path('lib/services/local_store.dart').read_text()
