import 'package:flutter/material.dart';

import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class FollowUpScreen extends StatefulWidget {
  final LocalStore store;
  final SyncSnapshot? snapshot;
  const FollowUpScreen({super.key, required this.store, this.snapshot});
  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen> {
  List<TeacherEvent> _items = [];
  String _filter = 'all';
  bool _archived = false, _busy = false, _loaded = false;
  String? _error;
  int _generation = 0;
  static const _labels = {
    'pending': 'À envoyer',
    'received': 'Reçu par le Principal',
    'accepted': 'Validé',
    'refused': 'Refusé',
  };
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    _reload();
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) _reload();
  }

  Future<void> _reload() async {
    final gen = ++_generation;
    try {
      final history = await widget.store.loadFollowUpHistory(
        archived: _archived,
      );
      final queue = _archived
          ? <TeacherEvent>[]
          : await widget.store.loadQueue();
      if (!mounted || gen != _generation) return;
      setState(() {
        _items = [...queue, ...history]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _loaded = true;
        _error = null;
      });
    } catch (_) {
      if (mounted && gen == _generation) {
        setState(
          () => _error =
              'Le suivi ne peut pas être affiché. Aucune donnée n’a été supprimée.',
        );
      }
    }
  }

  Future<void> _reset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remettre le suivi à zéro ?'),
        content: const Text(
          'Les saisies déjà envoyées seront rangées dans les anciennes saisies. Les compteurs correspondants seront remis à zéro.\n\nLes saisies à envoyer restent visibles. Aucune donnée scolaire du Principal n’est supprimée. Toute nouvelle décision réapparaîtra dans le suivi.',
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
    setState(() => _busy = true);
    try {
      await widget.store.resetFollowUp();
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Suivi remis à zéro. Les saisies à envoyer sont conservées.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Remise à zéro impossible. Le suivi est conservé.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items
        .where((e) => _filter == 'all' || e.status == _filter)
        .toList();
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
                  DropdownButton<String>(
                    value: _filter,
                    isExpanded: true,
                    items: ['all', ..._labels.keys]
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              s == 'all' ? 'Toutes les saisies' : _labels[s]!,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (s) => setState(() => _filter = s ?? 'all'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Voir les anciennes saisies'),
                    value: _archived,
                    onChanged: _busy
                        ? null
                        : (v) {
                            setState(() => _archived = v);
                            _reload();
                          },
                  ),
                  if (!_archived)
                    OutlinedButton.icon(
                      onPressed:
                          _busy || !_items.any((e) => e.status != 'pending')
                          ? null
                          : _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Remettre le suivi à zéro'),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                  ? const Center(
                      child: Text('Aucune saisie dans cette catégorie.'),
                    )
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
                        final d = e.createdAt.toLocal();
                        final when =
                            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                        final note = (e.payload['_reviewNote'] ?? '')
                            .toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.status == 'accepted'
                                ? Icons.verified_outlined
                                : e.status == 'refused'
                                ? Icons.error_outline
                                : Icons.schedule,
                          ),
                          title: Text('$student — ${e.displayType}'),
                          subtitle: Text(
                            '${_labels[e.status] ?? 'À vérifier'} · $when${note.isEmpty ? '' : '\nMotif : $note'}',
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
