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
  const SetupScreen({super.key, required this.store, required this.api, required this.onConnected});
  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final host = TextEditingController();
  final code = TextEditingController();
  bool busy = false;
  String? error;
  String status = 'Recopiez l’adresse affichée dans GESTCOURS Principal, puis votre code professeur.';

  @override
  void initState() {
    super.initState();
    _loadPrevious();
  }

  Future<void> _loadPrevious() async {
    final previous = await widget.store.loadConfig();
    if (!mounted || previous == null) return;
    host.text = previous.host;
    code.text = previous.code;
  }

  Future<void> connect() async {
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim();
    final enteredCode = code.text.trim();
    if (enteredHost.isEmpty) {
      setState(() => error = 'Saisissez l’adresse du PC Principal.');
      return;
    }
    if (!RegExp(r'^\d{6}$').hasMatch(enteredCode)) {
      setState(() => error = 'Saisissez le code professeur à 6 chiffres.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      status = 'Connexion à GESTCOURS Principal…';
    });

    final lanPermission = await PlatformPermissions.ensureLocalNetwork();
    if (!lanPermission.mayProceed) {
      if (mounted) {
        setState(() {
          busy = false;
          error = lanPermission.message;
          status = 'Autorisation réseau local nécessaire.';
        });
      }
      return;
    }

    try {
      final c = await widget.api.pairAddress(enteredHost, enteredCode);
      if (mounted) setState(() => status = 'Connexion trouvée. Synchronisation de vos classes…');
      final snapshot = await widget.api.sync(c);
      await widget.store.saveConfig(c);
      await widget.store.saveSnapshot(snapshot);
      if (!mounted) return;
      widget.onConnected(c);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = e.toString();
        status = 'Connexion non établie.';
      });
    }
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanner()),
    );
    if (result == null) return;
    try {
      final value = result.trim();
      final p = value.split('|');
      if (p.length == 5 && p[0] == 'ECOLEPRO') {
        host.text = p[1].trim();
        code.text = p[4].trim();
        await connect();
        return;
      }
      if (p.length >= 3 && p[0] == 'GESTCOURS') {
        host.text = p[1].trim();
        code.text = p[2].trim();
        await connect();
        return;
      }
      setState(() => error = 'QR GESTCOURS non reconnu.');
    } catch (_) {
      setState(() => error = 'QR GESTCOURS non reconnu.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: const Text('GESTCOURS • PROF')),
        body: SafeArea(
          child: LayoutBuilder(builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 620 ? 520.0 : constraints.maxWidth;
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
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF183D39), Color(0xFF286F66)],
                            ),
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: const [BoxShadow(color: Color(0x16000000), blurRadius: 24, offset: Offset(0, 10))],
                          ),
                          child: Column(children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(color: Colors.white.withOpacity(.12), borderRadius: BorderRadius.circular(17)),
                              child: const Icon(Icons.lan_rounded, size: 29, color: Colors.white),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Connexion au Principal',
                              style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -.3),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Même Wi-Fi ou réseau local • adresse + code mémorisés après la première connexion',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withOpacity(.76), height: 1.3),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: host,
                          enabled: !busy,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Adresse du PC Principal',
                            hintText: '192.168.1.20',
                            prefixIcon: Icon(Icons.computer_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: code,
                          enabled: !busy,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: 6),
                          decoration: const InputDecoration(
                            labelText: 'Code professeur',
                            hintText: '123456',
                            counterText: '',
                            prefixIcon: Icon(Icons.key_rounded),
                          ),
                          onSubmitted: (_) { if (!busy) connect(); },
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F5F3),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(right: 11, top: 2),
                                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: Icon(Icons.info_outline, size: 20),
                              ),
                            Expanded(child: Text(status)),
                          ]),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: busy ? null : connect,
                          icon: const Icon(Icons.login_rounded),
                          label: Text(busy ? 'CONNEXION…' : 'SE CONNECTER'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: busy ? null : scanQr,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scanner un QR GESTCOURS (option)'),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'L’adresse à recopier est affichée dans Principal > Réseau enseignants. Le port et votre nom ne sont pas à saisir.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
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
        appBar: AppBar(title: const Text('Scanner le QR GESTCOURS')),
        body: MobileScanner(onDetect: (capture) {
          if (finished) return;
          final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
          if (value != null && value.isNotEmpty) {
            finished = true;
            Navigator.of(context).pop(value);
          }
        }),
      );
}
