import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/principal_config.dart';
import '../services/local_store.dart';
import '../services/principal_api.dart';
import '../services/platform_permissions.dart';

class SetupScreen extends StatefulWidget {
  final LocalStore store;
  final PrincipalApi api;
  final void Function(PrincipalConfig) onConnected;
  const SetupScreen({
    super.key,
    required this.store,
    required this.api,
    required this.onConnected,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final host = TextEditingController();
  final port = TextEditingController(text: '${PrincipalApi.defaultPrincipalPort}');
  final teacher = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String? error;
  String? progress;

  PrincipalConfig get config => PrincipalConfig(
        host: host.text.trim(),
        port: int.tryParse(port.text.trim()) ?? PrincipalApi.defaultPrincipalPort,
        teacher: teacher.text.trim(),
        code: code.text.trim(),
      );

  Future<bool> _checkPermission() async {
    final lanPermission = await PlatformPermissions.ensureLocalNetwork();
    if (!lanPermission.mayProceed) {
      setState(() {
        busy = false;
        progress = null;
        error = lanPermission.message;
      });
      return false;
    }
    return true;
  }

  Future<void> _finishConnection(PrincipalConfig c) async {
    try {
      final snapshot = await widget.api.sync(c);
      await widget.store.saveConfig(c);
      await widget.store.saveSnapshot(snapshot);
      if (!mounted) return;
      widget.onConnected(c);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        progress = null;
        error = e.toString();
      });
    }
  }

  Future<void> connectAutomatic() async {
    FocusScope.of(context).unfocus();
    final enteredCode = code.text.trim();
    if (!RegExp(r'^\\d{6}$').hasMatch(enteredCode)) {
      setState(() => error = 'Saisissez uniquement votre code professeur à 6 chiffres.');
      return;
    }

    setState(() {
      busy = true;
      error = null;
      progress = 'Recherche automatique de GESTCOURS Principal…';
    });
    if (!await _checkPermission()) return;

    try {
      final previous = await widget.store.loadConfig();
      final found = await widget.api.discoverByCode(enteredCode, previous: previous);
      if (!mounted) return;
      host.text = found.host;
      port.text = '${found.port}';
      teacher.text = found.teacher;
      setState(() => progress = 'PC Principal trouvé. Synchronisation de vos classes…');
      await _finishConnection(found);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        progress = null;
        error = e.toString();
      });
    }
  }

  Future<void> connectManual() async {
    FocusScope.of(context).unfocus();
    final c = config;
    if (c.host.isEmpty || c.port <= 0 || c.teacher.isEmpty || c.code.isEmpty) {
      setState(() => error = 'Adresse, port, professeur et code sont obligatoires en mode manuel.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      progress = 'Connexion au PC Principal…';
    });
    if (!await _checkPermission()) return;
    final ok = await widget.api.ping(c);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        busy = false;
        progress = null;
        error =
            'Cette adresse ne répond pas. Le port normal de GESTCOURS Principal est '
            '${PrincipalApi.defaultPrincipalPort}.';
      });
      return;
    }
    await _finishConnection(c);
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanner()),
    );
    if (result == null) return;
    try {
      final p = result.split('|');
      if (p.length == 5 && p[0] == 'ECOLEPRO') {
        setState(() {
          host.text = p[1];
          port.text = p[2];
          teacher.text = p[3];
          code.text = p[4];
          error = null;
        });
        await connectManual();
      } else {
        setState(() => error = 'QR non reconnu.');
      }
    } catch (_) {
      setState(() => error = 'QR non reconnu.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('GESTCOURS • PROF')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth > 620 ? 560.0 : constraints.maxWidth;
              return ListView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  56 + MediaQuery.of(context).padding.bottom + MediaQuery.of(context).viewInsets.bottom,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF183D39), Color(0xFF286F66)],
                              ),
                              borderRadius: BorderRadius.circular(26),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x16000000),
                                  blurRadius: 24,
                                  offset: Offset(0, 10),
                                )
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(.12),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(Icons.wifi_find, size: 25, color: Colors.white),
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Connexion simple',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Même Wi-Fi que le PC Principal • entrez seulement votre code à 6 chiffres',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white.withOpacity(.72)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: code,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Code professeur à 6 chiffres',
                              prefixIcon: Icon(Icons.key_outlined),
                            ),
                          ),
                          if (progress != null) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(progress!)),
                              ],
                            ),
                          ],
                          if (error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: busy ? null : connectAutomatic,
                            icon: const Icon(Icons.wifi_find),
                            label: Text(busy ? 'Recherche…' : 'SE CONNECTER'),
                          ),
                          const SizedBox(height: 10),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Connexion avancée (si nécessaire)'),
                            subtitle: const Text('Adresse IP et port cachés en utilisation normale'),
                            children: [
                              TextField(
                                controller: teacher,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Nom du professeur (mode avancé)',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: host,
                                keyboardType: TextInputType.url,
                                decoration: const InputDecoration(
                                  labelText: 'Adresse IP du PC Principal',
                                  hintText: '192.168.1.10',
                                  prefixIcon: Icon(Icons.computer),
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: port,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Port',
                                  prefixIcon: Icon(Icons.lan_outlined),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: busy ? null : connectManual,
                                icon: const Icon(Icons.login),
                                label: const Text('Connexion manuelle'),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: busy ? null : scanQr,
                                icon: const Icon(Icons.qr_code_scanner),
                                label: const Text('Scanner un QR code'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'En utilisation normale, vous ne saisissez plus le nom du professeur, l’adresse IP ni le port.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}

class _QrScanner extends StatefulWidget {
  const _QrScanner();
  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  bool finished = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scanner le QR du Principal')),
        body: MobileScanner(
          onDetect: (capture) {
            if (finished) return;
            final value =
                capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
            if (value != null && value.isNotEmpty) {
              finished = true;
              Navigator.of(context).pop(value);
            }
          },
        ),
      );
}
