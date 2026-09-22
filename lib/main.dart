import 'package:flutter/material.dart';
import 'models/principal_config.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/local_store.dart';
import 'services/principal_api.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EcoleGestionProfApp());
}

class EcoleGestionProfApp extends StatefulWidget {
  const EcoleGestionProfApp({super.key});
  @override
  State<EcoleGestionProfApp> createState() => _EcoleGestionProfAppState();
}

class _EcoleGestionProfAppState extends State<EcoleGestionProfApp> {
  final store = LocalStore();
  final api = const PrincipalApi();
  PrincipalConfig? config;
  bool loaded = false;
  String? startupError;

  @override
  void initState() { super.initState(); init(); }

  Future<void> init() async {
    try { config = await store.loadConfig(); }
    catch (e) { startupError = e.toString(); }
    if (mounted) setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'GESTCOURS Prof',
        theme: AppTheme.light(),
        home: !loaded
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : startupError != null
                ? Scaffold(appBar: AppBar(title: const Text('GESTCOURS Prof')), body: Center(child: Padding(padding: const EdgeInsets.all(24), child: SelectableText('Données locales illisibles, conservées sans remplacement.\n$startupError'))))
            : config == null
                ? SetupScreen(store: store, api: api, onConnected: (c) => setState(() => config = c))
                : HomeScreen(config: config!, store: store, api: api, onDisconnect: () => setState(() => config = null)),
      );
}
