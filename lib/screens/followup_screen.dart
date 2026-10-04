import 'package:flutter/material.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/user_message.dart';

class FollowupScreen extends StatefulWidget {
  final LocalStore store;
  final SyncSnapshot? snapshot;
  const FollowupScreen({super.key, required this.store, this.snapshot});
  @override
  State<FollowupScreen> createState() => _FollowupScreenState();
}

class _FollowupScreenState extends State<FollowupScreen> {
  List<TeacherEvent> items = [];
  String filter = 'all';
  bool archived = false, resetting = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_reload);
    _reload();
  }
  @override
  void dispose() {
    widget.store.removeListener(_reload);
    super.dispose();
  }
  Future<void> _reload() async {
    final request = ++generation;
    try {
      final result = await widget.store.loadFollowup(archived: archived);
      if (!mounted || request != generation) return;
      setState(() { items = result; error = null; });
    } catch (e) {
      if (mounted && request == generation) setState(() => error = userMessage(e));
    }
  }
  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Remettre le suivi à zéro ?'),
      content: const Text('Les saisies déjà transmises passeront dans les archives et leurs compteurs seront remis à zéro.\n\nLes saisies à envoyer restent visibles. Aucune saisie ni donnée du Principal ne sera supprimée. Une nouvelle décision du Principal réapparaîtra dans le suivi.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remettre à zéro')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => resetting = true);
    try {
      await widget.store.resetFollowup();
      if (!mounted) return;
      setState(() { archived = false; filter = 'all'; });
      await _reload();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Suivi remis à zéro. Les saisies à envoyer sont conservées.'),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userMessage(e))));
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }
  String _label(String status) => const {
    'pending': 'À envoyer', 'received': 'Reçu par le Principal',
    'accepted': 'Validé', 'refused': 'Refusé',
  }[status] ?? 'Saisie';
  String _when(DateTime d) {
    final local = d.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} à ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  @override
  Widget build(BuildContext context) {
    final shown = items.where((e) => filter == 'all' || e.status == filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des saisies')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('Suivi actuel'), selected: !archived, onSelected: (_) { setState(() { archived = false; filter = 'all'; }); _reload(); }),
            ChoiceChip(label: const Text('Archives'), selected: archived, onSelected: (_) { setState(() { archived = true; filter = 'all'; }); _reload(); }),
          ]),
          const SizedBox(height: 10),
          DropdownButton<String>(value: filter, isExpanded: true,
            items: ['all', if (!archived) 'pending', 'received', 'accepted', 'refused'].map((s) => DropdownMenuItem(value: s, child: Text(s == 'all' ? 'Toutes les saisies' : _label(s)))).toList(),
            onChanged: (v) => setState(() => filter = v ?? 'all')),
          if (!archived) OutlinedButton.icon(
            key: const ValueKey('reset-followup'),
            onPressed: resetting || !items.any((e) => e.status != 'pending') ? null : _reset,
            icon: const Icon(Icons.restart_alt), label: const Text('Remettre le suivi à zéro')),
          if (archived) const Text('Les saisies restent conservées. Elles ne sont pas renvoyées au Principal.'),
          if (error != null) Text(error!),
        ])),
        Expanded(child: shown.isEmpty ? const Center(child: Text('Aucune saisie dans cette catégorie.')) : ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), itemCount: shown.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (context, index) {
            final e = shown[index];
            final matching = widget.snapshot?.students.where((s) => s.id == e.studentId);
            final student = matching != null && matching.isNotEmpty ? matching.first.displayName : e.studentId.isEmpty ? 'Toute la classe' : 'Élève archivé';
            final note = (e.payload['_reviewNote'] ?? '').toString().trim();
            return ListTile(contentPadding: EdgeInsets.zero,
              leading: Icon(e.status == 'refused' ? Icons.error_outline : e.status == 'accepted' ? Icons.verified_outlined : Icons.schedule),
              title: Text('$student — ${e.displayType}'),
              subtitle: Text('${_label(e.status)} · ${_when(e.createdAt)}${note.isEmpty ? '' : '\nMotif : $note'}'));
          },
        )),
      ])),
    );
  }
}
