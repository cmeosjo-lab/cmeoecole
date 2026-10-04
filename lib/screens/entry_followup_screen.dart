import 'package:flutter/material.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/user_messages.dart';

class EntryFollowupScreen extends StatefulWidget {
  final LocalStore store;
  final SyncSnapshot? snapshot;
  const EntryFollowupScreen({super.key, required this.store, this.snapshot});
  @override
  State<EntryFollowupScreen> createState() => _EntryFollowupScreenState();
}

class _EntryFollowupScreenState extends State<EntryFollowupScreen> {
  List<TeacherEvent> entries = [];
  Set<String> archived = {};
  String filter = 'all';
  bool showArchived = false, busy = false, loaded = false;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.store.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final current = ++generation;
    try {
      final q = await widget.store.loadQueue();
      final h = await widget.store.loadTransmissionHistory();
      final a = await widget.store.archivedDashboardIds();
      if (!mounted || current != generation) return;
      setState(() {
        entries = [...q, ...h]
          ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
        archived = a;
        error = null;
        loaded = true;
      });
    } catch (e) {
      if (mounted && current == generation)
        setState(() {
          error = userMessage(e);
          loaded = true;
        });
    }
  }

  bool _completed(TeacherEvent e) =>
      e.status == 'accepted' || e.status == 'refused';
  bool _hidden(TeacherEvent e) => _completed(e) && archived.contains(e.id);
  String _label(String status) =>
      const {
        'pending': 'À envoyer',
        'received': 'En attente de validation',
        'accepted': 'Validée',
        'refused': 'Refusée',
      }[status] ??
      'À vérifier';
  Future<void> _reset() async {
    if (busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remettre les compteurs à zéro ?'),
        content: const Text(
          'Les saisies validées et refusées seront rangées dans les archives du suivi.\n\nLes saisies à envoyer et celles en attente de validation restent visibles. Aucune information scolaire ne sera effacée, ni ici ni sur le Principal.',
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
    if (confirm != true || !mounted) return;
    setState(() => busy = true);
    try {
      final count = await widget.store.resetDashboardHistory();
      await _refresh();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count saisie(s) rangée(s). Le travail en cours est conservé.',
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = entries
        .where(
          (e) =>
              (showArchived || !_hidden(e)) &&
              (filter == 'all' || e.status == filter),
        )
        .toList();
    final completed = entries.where((e) => _completed(e) && !_hidden(e)).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des saisies')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: filter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Afficher'),
                    items: ['all', 'pending', 'received', 'accepted', 'refused']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s == 'all' ? 'Toutes les saisies' : _label(s),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (s) => setState(() => filter = s ?? 'all'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Voir aussi les saisies archivées'),
                    value: showArchived,
                    onChanged: (v) => setState(() => showArchived = v ?? false),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || completed == 0 || error != null
                        ? null
                        : _reset,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Remettre les compteurs à zéro'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            if (error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
            Expanded(
              child: !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? const Center(
                      child: Text('Aucune saisie dans cette catégorie.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final e = visible[index];
                        final matches = widget.snapshot?.students.where(
                          (s) => s.id == e.studentId,
                        );
                        final name = matches != null && matches.isNotEmpty
                            ? matches.first.displayName
                            : e.studentId.isEmpty
                            ? 'Toute la classe'
                            : 'Élève archivé';
                        final date = e.createdAt.toLocal();
                        final when =
                            '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
                        final note = (e.payload['_reviewNote'] ?? '')
                            .toString()
                            .trim();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.status == 'accepted'
                                ? Icons.verified_outlined
                                : e.status == 'refused'
                                ? Icons.error_outline
                                : Icons.schedule,
                          ),
                          title: Text('$name — ${e.displayType}'),
                          subtitle: Text(
                            '${_label(e.status)} · $when${_hidden(e) ? ' · Archivée' : ''}${note.isEmpty ? '' : '\nMotif : $note'}',
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
