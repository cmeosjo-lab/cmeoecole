import 'package:flutter/material.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/user_message.dart';

class TransmissionScreen extends StatefulWidget {
  final LocalStore store;
  final SyncSnapshot? snapshot;
  const TransmissionScreen({super.key, required this.store, this.snapshot});
  @override
  State<TransmissionScreen> createState() => _TransmissionScreenState();
}

class _TransmissionScreenState extends State<TransmissionScreen> {
  List<TeacherEvent> events = [];
  String filter = 'all';
  bool archived = false, resetting = false, loaded = false;
  String? error;
  int generation = 0;
  String label(String status) =>
      const {
        'pending': 'À envoyer',
        'received': 'À valider',
        'accepted': 'Validée',
        'refused': 'Refusée',
      }[status] ??
      'À vérifier';
  @override
  void initState() {
    super.initState();
    widget.store.addListener(refresh);
    refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(refresh);
    super.dispose();
  }

  Future<void> refresh() async {
    final gen = ++generation;
    try {
      final q = archived ? <TeacherEvent>[] : await widget.store.loadQueue();
      final h = await widget.store.loadDashboardHistory(archived: archived);
      if (!mounted || gen != generation) return;
      setState(() {
        events = [...q, ...h]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        error = null;
        loaded = true;
      });
    } catch (e) {
      if (mounted && gen == generation)
        setState(() {
          error = userMessage(e);
          loaded = true;
        });
    }
  }

  Future<void> reset() async {
    if (resetting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remettre le suivi à zéro ?'),
        content: const Text(
          'Les saisies déjà envoyées seront rangées dans les archives du suivi. Les compteurs du tableau de bord repartiront à zéro.\n\nLes saisies à envoyer restent visibles. Rien n’est effacé du téléphone ni du Principal. Une nouvelle décision du Principal réapparaîtra dans le suivi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remettre à zéro'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => resetting = true);
    try {
      await widget.store.resetDashboardTracking();
      if (!mounted) return;
      setState(() {
        archived = false;
        filter = 'all';
      });
      await refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Suivi remis à zéro. Les saisies sont conservées.'),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = events
        .where((e) => filter == 'all' || e.status == filter)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des saisies')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  OutlinedButton.icon(
                    onPressed: resetting ? null : reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Remettre le suivi à zéro'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Voir les saisies archivées'),
                    value: archived,
                    onChanged: (v) {
                      setState(() {
                        archived = v;
                        filter = 'all';
                      });
                      refresh();
                    },
                  ),
                  DropdownButton<String>(
                    value: filter,
                    isExpanded: true,
                    items:
                        [
                              'all',
                              if (!archived) 'pending',
                              'received',
                              'accepted',
                              'refused',
                            ]
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s == 'all' ? 'Toutes les saisies' : label(s),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => filter = v ?? 'all'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(error!),
                      ),
                    )
                  : items.isEmpty
                  ? const Center(child: Text('Aucune saisie à afficher.'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final matching = widget.snapshot?.students.where(
                          (s) => s.id == e.studentId,
                        );
                        final student = matching != null && matching.isNotEmpty
                            ? matching.first.displayName
                            : e.studentId.isEmpty
                            ? 'Toute la classe'
                            : 'Élève archivé';
                        final date = e.createdAt.toLocal();
                        final note = (e.payload['_reviewNote'] ?? '')
                            .toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.status == 'accepted'
                                ? Icons.check_circle_outline
                                : e.status == 'refused'
                                ? Icons.error_outline
                                : Icons.schedule,
                          ),
                          title: Text('$student — ${e.displayType}'),
                          subtitle: Text(
                            '${label(e.status)} · ${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}${note.isEmpty ? '' : '\nMotif : $note'}',
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
