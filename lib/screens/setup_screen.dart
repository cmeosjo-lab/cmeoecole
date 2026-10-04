import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/principal_config.dart';
import '../services/local_store.dart';
import '../services/principal_api.dart';
import '../services/platform_permissions.dart';
import '../services/pairing_code.dart';
import '../services/user_messages.dart';

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
  bool busy = false;
  int _attempt = 0;
  String _expectedPrincipal = '';

  String? error;
  String status =
      'Scannez votre QR affiché sur le Principal, ou saisissez votre adresse et votre code.';

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

  void cancelConnection() {
    _attempt++;
    if (mounted) {
      setState(() {
        busy = false;
        status = 'Connexion interrompue sur ce téléphone.';
      });
    }
  }

  Future<void> connect() async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final enteredHost = host.text.trim(), enteredCode = code.text.trim();
    if (enteredHost.isEmpty || !RegExp(r'^\d{6}$').hasMatch(enteredCode)) {
      setState(
        () => error =
            'Saisissez l’adresse du Principal et le code à 6 chiffres, ou scannez votre QR.',
      );
      return;
    }
    final attempt = ++_attempt;
    setState(() {
      busy = true;
      error = null;
      status = 'Connexion au Principal…';
    });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!mounted || attempt != _attempt) return;
      if (!permission.mayProceed) {
        throw PrincipalApiException(permission.message);
      }
      final deviceId = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (mounted && attempt == _attempt) {
        try {
          final c = await widget.api.pairAddress(
            enteredHost,
            enteredCode,
            deviceId: deviceId,
          );
          if (!mounted || attempt != _attempt) return;
          if (_expectedPrincipal.isNotEmpty &&
              c.principalId != _expectedPrincipal) {
            throw PrincipalApiException(
              'Ce QR ne correspond pas au Principal trouvé. Demandez un nouveau QR au responsable.',
            );
          }
          setState(() {
            status = 'Connexion autorisée. Réception de vos classes…';
          });
          final snapshot = await widget.api.sync(c, deviceId: deviceId);
          if (!mounted || attempt != _attempt) return;
          await widget.store.activateSession(c, snapshot);
          if (!mounted || attempt != _attempt) return;
          widget.onConnected(c);
          return;
        } on PrincipalApprovalPending catch (request) {
          if (!mounted || attempt != _attempt) return;
          setState(() {
            status =
                'Demande envoyée pour ${request.teacher}. Le responsable doit l’accepter sur le tableau de bord du Principal.';
          });
          if (DateTime.now().isAfter(deadline)) {
            throw PrincipalApiException(
              'La demande attend toujours le responsable. Après son accord, appuyez sur Se connecter.',
            );
          }
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } catch (e) {
      if (mounted && attempt == _attempt) {
        setState(() {
          error = userMessage(e);
          status = 'Connexion non établie.';
        });
      }
    } finally {
      if (mounted && attempt == _attempt) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> scanQr() async {
    final result = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const _QrScanner()));
    if (result == null || !mounted) return;
    try {
      final pairing = PairingCode.parse(result);
      host.text = pairing.address;
      code.text = pairing.code;
      _expectedPrincipal = pairing.principalId;
    } on FormatException {
      setState(
        () => error =
            'QR non reconnu. Scannez le QR personnel affiché par le Principal.',
      );
      return;
    }
    await connect();
  }

  @override
  void dispose() {
    _attempt++;
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
                              'Même Wi-Fi ou réseau local • adresse + code mémorisés après la première connexion',
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
                        label: const Text('Scanner mon QR de connexion'),
                      ),
                      const SizedBox(height: 14),
                      const Text('Ou se connecter avec une adresse et un code'),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (_) => _expectedPrincipal = '',
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
                        onPressed: busy ? null : connect,
                        icon: const Icon(Icons.login_rounded),
                        label: Text(busy ? 'CONNEXION…' : 'SE CONNECTER'),
                      ),
                      const SizedBox(height: 10),
                      if (busy)
                        OutlinedButton(
                          onPressed: cancelConnection,
                          child: const Text('Annuler l’attente'),
                        ),
                      const SizedBox(height: 14),
                      const Text(
                        'Le responsable affiche votre QR depuis le tableau de bord du Principal. Il doit ensuite autoriser votre appareil.',
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
