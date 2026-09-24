import 'package:flutter/material.dart';
import 'models/principal_config.dart';
import 'screens/home_screen.dart';
import 'screens/setup_screen.dart';
import 'services/local_store.dart';
import 'services/principal_api.dart';
import 'services/sync_coordinator.dart';
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
  late final SyncCoordinator coordinator;
  PrincipalConfig? config;
  bool loaded = false;
  String? startupError;
  @override
  void initState() {
    super.initState();
    coordinator = SyncCoordinator(store, api);
    init();
  }

  Future<void> init() async {
    try {
      config = await store.loadConfig();
      coordinator.start();
    } catch (e) {
      startupError = e.toString();
    }
    if (mounted) setState(() => loaded = true);
  }

  @override
  void dispose() {
    coordinator.dispose();
    store.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'GESTCOURS Prof',
    theme: AppTheme.light(),
    home: !loaded
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : startupError != null
        ? Scaffold(
            appBar: AppBar(title: const Text('Protection des données')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(
                'Les données locales n’ont pas pu être ouvertes. Aucune remise à zéro n’a été effectuée.\n\nNe désinstallez pas l’application.\n\n$startupError',
              ),
            ),
          )
        : config == null
        ? SetupScreen(
            store: store,
            api: api,
            onConnected: (c) {
              if (!mounted) return;
              setState(() => config = c);
              coordinator.schedule(const Duration(seconds: 1));
            },
          )
        : HomeScreen(
            config: config!,
            store: store,
            api: api,
            coordinator: coordinator,
            onDisconnect: () {
              if (mounted) setState(() => config = null);
            },
          ),
  );
}
