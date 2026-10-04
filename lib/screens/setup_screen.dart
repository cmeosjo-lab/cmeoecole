import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/connection_qr.dart';
import '../models/principal_config.dart';
import '../services/local_store.dart';
import '../services/principal_api.dart';
import '../services/platform_permissions.dart';
import '../services/user_message.dart';

class SetupScreen extends StatefulWidget {
  final LocalStore store;
  final PrincipalApi api;
  final void Function(PrincipalConfig) onConnected;
  const SetupScreen({super.key, required this.store, required this.api, required this.onConnected});
  @override State<SetupScreen> createState() => _SetupScreenState();
}
class _SetupScreenState extends State<SetupScreen> {
  final host = TextEditingController(), code = TextEditingController();
  bool busy = false, waiting = false;
  int attempt = 0;
  String? error;
  String status = 'Scannez le QR affiché par le Principal ou saisissez votre connexion.';
  @override void initState() { super.initState(); _loadPrevious(); }
  Future<void> _loadPrevious() async {
    final previous = await widget.store.loadConfig();
    if (!mounted || previous == null || busy) return;
    host.text = '${previous.host}:${previous.port}'; code.text = previous.code;
  }
  void cancelWait() {
    attempt++;
    setState(() { busy = false; waiting = false; status = 'La demande reste visible sur le Principal. Vous pouvez réessayer.'; });
  }
  Future<void> connect({String expectedPrincipalId = ''}) async {
    if (busy) return;
    FocusScope.of(context).unfocus();
    final address = host.text.trim(), secret = code.text.trim();
    if (address.isEmpty || !RegExp(r'^\d{6}$').hasMatch(secret)) {
      setState(() => error = 'Renseignez l’adresse du Principal et votre code à 6 chiffres, ou scannez le QR.');
      return;
    }
    final thisAttempt = ++attempt;
    bool active() => mounted && thisAttempt == attempt;
    setState(() { busy = true; waiting = false; error = null; status = 'Connexion au Principal…'; });
    try {
      final permission = await PlatformPermissions.ensureLocalNetwork();
      if (!active()) return;
      if (!permission.mayProceed) throw PrincipalApiException(permission.message);
      final deviceId = await widget.store.getOrCreateDeviceId();
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (active()) {
        try {
          final c = await widget.api.pairAddress(address, secret, deviceId: deviceId, expectedPrincipalId: expectedPrincipalId);
          if (!active()) return;
          setState(() { waiting = false; status = 'Connexion autorisée. Vos classes arrivent…'; });
          final snapshot = await widget.api.sync(c, deviceId: deviceId);
          if (!active()) return;
          await widget.store.activateSession(c, snapshot);
          if (!active()) return;
          widget.onConnected(c);
          return;
        } on PrincipalApprovalPending {
          if (!active()) return;
          if (DateTime.now().isAfter(deadline)) throw PrincipalApiException('La demande attend toujours le responsable. Après son accord, appuyez sur Se connecter.');
          setState(() { waiting = true; status = 'Demande envoyée au Principal. Le responsable peut l’autoriser sur son tableau de bord. La connexion se terminera automatiquement.'; });
          await Future<void>.delayed(const Duration(seconds: 4));
        }
      }
    } catch (e) {
      if (active()) setState(() { error = userMessage(e); status = 'Connexion non établie.'; });
    } finally {
      if (active()) setState(() { busy = false; waiting = false; });
    }
  }
  Future<void> scanQr() async {
    final result = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ConnectionQrScanner()));
    if (result == null || !mounted) return;
    try {
      final qr = ConnectionQr.parse(result);
      host.text = qr.address; code.text = qr.code;
      await connect(expectedPrincipalId: qr.principalId);
    } on FormatException {
      if (mounted) setState(() => error = 'Ce QR n’est pas un QR de connexion GESTCOURS. Demandez-le au responsable.');
    }
  }
  @override void dispose() { attempt++; host.dispose(); code.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('GESTCOURS Prof')),
    body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: ListView(
      padding: const EdgeInsets.all(20), keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        const Icon(Icons.school_outlined, size: 48), const SizedBox(height: 16),
        Text('Connexion à votre établissement', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12), const Text('Connectez le téléphone au même Wi-Fi que le PC Principal.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: busy ? null : scanQr, icon: const Icon(Icons.qr_code_scanner), label: const Text('Scanner le QR de connexion')),
        const SizedBox(height: 8), const Text('Sur le PC : Réseau enseignants → QR de connexion.', textAlign: TextAlign.center),
        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('ou saisir la connexion')), Expanded(child: Divider())])),
        TextField(controller: host, enabled: !busy, keyboardType: TextInputType.url, autocorrect: false, decoration: const InputDecoration(labelText: 'Adresse du Principal', hintText: 'Adresse affichée sur le PC', prefixIcon: Icon(Icons.computer))),
        const SizedBox(height: 14),
        TextField(controller: code, enabled: !busy, keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly], obscureText: true,
          decoration: const InputDecoration(labelText: 'Code professeur', counterText: '', prefixIcon: Icon(Icons.key_outlined)), onSubmitted: (_) { if (!busy) connect(); }),
        const SizedBox(height: 18),
        OutlinedButton.icon(onPressed: busy ? null : () => connect(), icon: const Icon(Icons.login), label: const Text('Se connecter')),
        const SizedBox(height: 16), if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 12), Text(status, textAlign: TextAlign.center),
        if (waiting) TextButton(onPressed: cancelWait, child: const Text('Arrêter l’attente')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: 24),
      ],
    )))),
  );
}
class ConnectionQrScanner extends StatefulWidget {
  const ConnectionQrScanner({super.key});
  @override State<ConnectionQrScanner> createState() => _ConnectionQrScannerState();
}
class _ConnectionQrScannerState extends State<ConnectionQrScanner> {
  final controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool finished = false;
  @override void dispose() { unawaited(controller.dispose()); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scanner le QR du Principal')),
    body: MobileScanner(controller: controller, onDetect: (capture) {
      if (finished || !mounted) return;
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw == null || raw.isEmpty) continue;
        finished = true; Navigator.pop(context, raw); return;
      }
    }, errorBuilder: (context, error) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('La caméra n’est pas disponible. Autorisez-la dans les réglages du téléphone ou utilisez l’adresse et le code professeur.', textAlign: TextAlign.center)))),
  );
}
