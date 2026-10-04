import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../services/local_store.dart';
import '../services/principal_api.dart';
import '../services/sync_coordinator.dart';
import '../widgets/school_header.dart';
import 'classes_screen.dart';
import 'followup_screen.dart';
import '../services/user_message.dart';

class HomeScreen extends StatefulWidget {
  final PrincipalConfig config;
  final LocalStore store;
  final PrincipalApi api;
  final SyncCoordinator coordinator;
  final VoidCallback onDisconnect;
  const HomeScreen({
    super.key,
    required this.config,
    required this.store,
    required this.api,
    required this.coordinator,
    required this.onDisconnect,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SyncSnapshot? snapshot;
  PrincipalConfig? actualConfig;
  DateTime? lastSync;
  int pending = 0, received = 0, accepted = 0, refused = 0, _generation = 0;
  String? localError;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    widget.coordinator.addListener(_changed);
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    widget.coordinator.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) _refresh();
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    try {
      final config = await widget.store.loadConfig();
      final s = await widget.store.loadSnapshot();
      final q = await widget.store.loadQueue();
      final h = await widget.store.loadFollowup();
      final last = await widget.store.lastSuccessfulSync();
      if (!mounted || generation != _generation) return;
      setState(() {
        actualConfig = config;
        snapshot = s;
        pending = q.length;
        lastSync = last;
        localError = null;
        received = h.where((e) => e.status == 'received').length;
        accepted = h.where((e) => e.status == 'accepted').length;
        refused = h.where((e) => e.status == 'refused').length;
      });
    } catch (e) {
      if (mounted) setState(() => localError = userMessage(e));
    }
  }

  Future<void> _sync() async {
    await widget.coordinator.synchronize();
    await _refresh();
  }

  String _when(DateTime? d) => d == null
      ? 'Pas encore effectuée'
      : '${d.toLocal().day.toString().padLeft(2, '0')}/${d.toLocal().month.toString().padLeft(2, '0')} à ${d.toLocal().hour.toString().padLeft(2, '0')}:${d.toLocal().minute.toString().padLeft(2, '0')}';
  Future<void> _history() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FollowupScreen(store: widget.store, snapshot: snapshot),
      ),
    );
    await _refresh();
  }

  Future<void> _backup() async {
    try {
      final raw = await widget.store.exportBundle();
      await Clipboard.setData(ClipboardData(text: raw));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sauvegarde copiée. Collez-la dans un fichier texte privé. Elle contient les données de cet appareil.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userMessage(
                e,
                fallback: 'La sauvegarde n’a pas pu être préparée.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _restore() async {
    final field = TextEditingController();
    try {
      final raw = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restaurer une sauvegarde'),
          content: TextField(
            controller: field,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Collez le contenu du fichier de sauvegarde',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('Restaurer sans effacer'),
            ),
          ],
        ),
      );
      if (raw == null || raw.trim().isEmpty) return;
      await widget.store.importBundle(raw);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sauvegarde fusionnée. Aucune saisie locale supprimée.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userMessage(
                e,
                fallback:
                    'Cette sauvegarde ne peut pas être restaurée. Les données actuelles sont conservées.',
              ),
            ),
          ),
        );
      }
    } finally {
      field.dispose();
    }
  }

  Future<void> _changeAddress() async {
    final old = await widget.store.loadConfig();
    if (old == null || !mounted) return;
    final field = TextEditingController(text: '${old.host}:${old.port}');
    try {
      final raw = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Adresse du PC Principal'),
          content: TextField(
            controller: field,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Nouvelle adresse affichée sur le PC',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('Vérifier et enregistrer'),
            ),
          ],
        ),
      );
      if (raw == null || raw.trim().isEmpty) return;
      await widget.coordinator.maintain(() async {
        final device = await widget.store.getOrCreateDeviceId();
        final found = await widget.api.pairAddress(
          raw,
          old.code,
          deviceId: device,
        );
        if (found.teacher.trim().toLowerCase() !=
                old.teacher.trim().toLowerCase() ||
            (old.principalId.isNotEmpty &&
                found.principalId != old.principalId)) {
          throw StateError(
            'Ce PC ou ce professeur ne correspond pas à votre connexion. Aucune donnée locale modifiée.',
          );
        }
        final fresh = await widget.api.sync(found, deviceId: device);
        await widget.store.activateSession(found, fresh);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Adresse actualisée. Les saisies locales sont conservées.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userMessage(
                e,
                fallback:
                    'La connexion n’a pas été modifiée. Vérifiez les informations auprès du Principal.',
              ),
            ),
          ),
        );
      }
    } finally {
      field.dispose();
    }
  }

  Future<void> _disconnect() async {
    if (widget.coordinator.busy) return;
    try {
      await widget.store.clearConfig();
      widget.onDisconnect();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coordinator;
    final s = snapshot;
    final error =
        localError ?? (c.lastError == null ? null : userMessage(c.lastError!));
    final headline = localError != null
        ? 'Attention : stockage local'
        : c.busy
        ? 'Synchronisation en cours…'
        : error != null
        ? 'Connexion à rétablir'
        : pending > 0
        ? '$pending saisie(s) à envoyer'
        : 'Toutes les saisies sont transmises';
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.displayTitle ?? 'GESTCOURS Prof'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'address':
                  await _changeAddress();
                case 'history':
                  await _history();
                case 'backup':
                  await _backup();
                case 'restore':
                  await _restore();
                case 'disconnect':
                  await _disconnect();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'history',
                child: Text('Suivi des saisies'),
              ),
              PopupMenuItem(
                value: 'address',
                enabled: !c.busy,
                child: const Text('Modifier l’adresse du Principal'),
              ),
              const PopupMenuItem(
                value: 'backup',
                child: Text('Sauvegarder cet appareil'),
              ),
              PopupMenuItem(
                value: 'restore',
                enabled: !c.busy,
                child: const Text('Restaurer une sauvegarde'),
              ),
              PopupMenuItem(
                value: 'disconnect',
                enabled: !c.busy,
                child: const Text('Déconnecter cet appareil'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _sync,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              SchoolHeader(
                title: s?.displayTitle ?? 'GESTCOURS Prof',
                subtitle: s?.schoolYear ?? '',
                teacher: widget.config.teacher,
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            error != null
                                ? Icons.wifi_off
                                : pending > 0
                                ? Icons.outbox_outlined
                                : Icons.check_circle_outline,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              headline,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Dernière synchronisation réussie : ${_when(lastSync)}',
                      ),
                      if (pending > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '$pending saisie(s) conservées sur cet appareil.',
                          ),
                        ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(error),
                        ),
                      if (c.busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  onTap: _history,
                  title: const Text('Suivi des saisies'),
                  subtitle: Text(
                    '$received à valider · $accepted validée(s) · $refused refusée(s)',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: s == null
                    ? null
                    : () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClassesScreen(
                              config: widget.config,
                              snapshot: s,
                              store: widget.store,
                            ),
                          ),
                        );
                        await _refresh();
                      },
                icon: const Icon(Icons.groups_2_outlined),
                label: Text('Mes classes (${s?.classes.length ?? 0})'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: c.busy ? null : _sync,
                icon: const Icon(Icons.sync),
                label: const Text('Synchroniser maintenant'),
              ),
              const SizedBox(height: 16),
              const Text(
                'Envoi automatique après vos saisies et au retour dans l’application. Le PC Principal doit rester ouvert sur le même réseau local.',
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
