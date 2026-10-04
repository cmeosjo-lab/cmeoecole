import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/principal_config.dart';
import '../services/local_store.dart';
import '../services/principal_api.dart';
import '../services/platform_permissions.dart';
import '../services/user_message.dart';
import '../models/connection_qr.dart';

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
  final code = TextEditingController();
  bool busy = false, waiting = false;
  int attempt = 0;
  String? error;
  String status =
      'Scannez votre QR affiché par le Principal, ou saisissez votre adresse et votre code.';

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

  void _cancelWait() {
    attempt++;
    setState(() {
      busy = false;
      waiting = false;
      status = 'Vous pouvez relancer la connexion.';
    });
  }

  Future<void> connect({String expectedPrincipalId = ''}) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim(), enteredCode = code.text.trim();
    if (enteredHost.isEmpty || !RegExp(r'^\d{6}$').hasMatch(enteredCode)) {
      setState(
        () => error =
            'Scannez le QR ou renseignez l’adresse et le code professeur à 6 chiffres.',
      );
      return;
    }
    final run = ++attempt;
    setState(() {
      busy = true;
      waiting = false;
      error = null;
      status = 'Connexion au Principal…';
    });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!mounted || run != attempt) return;
      if (!permission.mayProceed) {
        setState(() {
          busy = false;
          error = 'Autorisez le réseau local pour vous connecter au Principal.';
        });
        return;
      }
      final device = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (mounted && run == attempt) {
        try {
          final config = await widget.api.pairAddress(
            enteredHost,
            enteredCode,
            deviceId: device,
            expectedPrincipalId: expectedPrincipalId,
          );
          if (!mounted || run != attempt) return;
          setState(() {
            waiting = false;
            status = 'Connexion acceptée. Récupération de vos classes…';
          });
          final snapshot = await widget.api.sync(config, deviceId: device);
          if (!mounted || run != attempt) return;
          await widget.store.activateSession(config, snapshot);
          if (!mounted || run != attempt) return;
          widget.onConnected(config);
          return;
        } on PrincipalApprovalPendingException {
          if (!mounted || run != attempt) return;
          if (DateTime.now().isAfter(deadline)) {
            setState(() {
              busy = false;
              waiting = false;
              status =
                  'La demande reste sur le Principal. Relancez la connexion après son acceptation.';
            });
            return;
          }
          setState(() {
            waiting = true;
            status =
                'Demande envoyée. L’administration doit cliquer sur Accepter dans le tableau de bord du Principal.';
          });
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } catch (e) {
      if (!mounted || run != attempt) return;
      setState(() {
        busy = false;
        waiting = false;
        error = userMessage(e);
        status = 'Connexion non établie.';
      });
    }
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScanner()));
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

  @override
  void dispose() {
    attempt++;
    host.dispose();
    code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(title: const Text('GESTCOURS • PROF')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth > 620
              ? 520.0
              : constraints.maxWidth;
          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              56 +
                  MediaQuery.of(context).padding.bottom +
                  MediaQuery.of(context).viewInsets.bottom,
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
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x16000000),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: const Icon(
                                Icons.lan_rounded,
                                size: 29,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Connexion au Principal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -.3,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Votre iPhone ou téléphone et le Principal doivent être sur le même Wi-Fi.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .76),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: busy ? null : scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scanner le QR du Principal'),
                      ),
                      const SizedBox(height: 14),
                      const Text('Ou saisir la connexion manuellement'),
                      const SizedBox(height: 12),
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Code professeur',
                          hintText: '123456',
                          counterText: '',
                          prefixIcon: Icon(Icons.key_rounded),
                        ),
                        onSubmitted: (_) {
                          if (!busy) connect();
                        },
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5F3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(right: 11, top: 2),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: Icon(Icons.info_outline, size: 20),
                              ),
                            Expanded(child: Text(status)),
                          ],
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: busy ? null : () => connect(),
                        icon: const Icon(Icons.login_rounded),
                        label: Text(busy ? 'CONNEXION…' : 'SE CONNECTER'),
                      ),
                      const SizedBox(height: 10),
                      if (waiting)
                        OutlinedButton(
                          onPressed: _cancelWait,
                          child: const Text('Annuler l’attente'),
                        ),
                      const SizedBox(height: 14),
                      const Text(
                        'Le QR est disponible sur le tableau de bord du Principal : Connexion par QR. Chaque professeur a son propre code.',
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
    appBar: AppBar(title: const Text('Scanner le QR GESTCOURS')),
    body: MobileScanner(
      errorBuilder: (context, error) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'La caméra n’est pas accessible. Autorisez-la dans les réglages, ou revenez à la connexion manuelle.',
          ),
        ),
      ),
      onDetect: (capture) {
        if (finished) return;
        final value = capture.barcodes.isNotEmpty
            ? capture.barcodes.first.rawValue
            : null;
        if (value != null && value.isNotEmpty) {
          finished = true;
          Navigator.of(context).pop(value);
        }
      },
    ),
  );
}
