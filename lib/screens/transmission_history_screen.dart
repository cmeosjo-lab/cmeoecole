import 'package:flutter/material.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/sync_coordinator.dart';

class TransmissionHistoryScreen extends StatefulWidget {
  final LocalStore store;
  final SyncCoordinator coordinator;
  final SyncSnapshot? snapshot;
  const TransmissionHistoryScreen({
    super.key,
    required this.store,
    required this.coordinator,
    this.snapshot,
  });
  @override
  State<TransmissionHistoryScreen> createState() =>
      _TransmissionHistoryScreenState();
}

class _TransmissionHistoryScreenState extends State<TransmissionHistoryScreen> {
  List<TeacherEvent> _queue = [], _history = [], _visible = [];
  String _filter = 'all';
  String? _error;
  bool _showPrevious = false, _resetting = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_reload);
    widget.coordinator.addListener(_updateBusy);
    _reload();
  }

  void _updateBusy() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    widget.store.removeListener(_reload);
    widget.coordinator.removeListener(_updateBusy);
    super.dispose();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final queue = await widget.store.loadQueue();
      final history = await widget.store.loadTransmissionHistory();
      final visible = await widget.store.loadDashboardHistory();
      if (!mounted || generation != _generation) return;
      setState(() {
        _queue = queue;
        _history = history;
        _visible = visible;
        _error = null;
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(
          () => _error =
              'Le suivi ne peut pas être ouvert. Les saisies sont conservées.',
        );
    }
  }

  String _label(String status) =>
      const {
        'pending': 'À envoyer',
        'received': 'Reçu par le Principal',
        'accepted': 'Validé',
        'refused': 'Refusé',
      }[status] ??
      status;
  Future<void> _reset() async {
    if (_resetting || widget.coordinator.busy || _visible.isEmpty) return;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remettre le suivi à zéro ?'),
        content: const Text(
          'Les compteurs des saisies reçues, validées et refusées seront remis à zéro.\n\nLes saisies à envoyer restent visibles et seront transmises normalement. Les anciennes saisies restent consultables avec « Afficher l’historique antérieur ».\n\nAucune donnée du Principal ne sera supprimée. Une nouvelle décision du Principal réapparaîtra dans le suivi.',
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
    if (answer != true || !mounted) return;
    setState(() => _resetting = true);
    try {
      await widget.coordinator.maintain(() async {
        await widget.store.resetTransmissionDashboard();
      });
      await _reload();
      if (mounted) {
        setState(() {
          _showPrevious = false;
          _filter = 'all';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Suivi remis à zéro. Les saisies à envoyer sont conservées.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La remise à zéro n’a pas pu être enregistrée. Aucune saisie supprimée.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items =
        [
            ..._queue,
            ...(_showPrevious ? _history : _visible),
          ].where((e) => _filter == 'all' || e.status == _filter).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: const Text('Suivi des saisies')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: DropdownButtonFormField<String>(
                key: ValueKey(_filter),
                initialValue: _filter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Afficher'),
                items: ['all', 'pending', 'received', 'accepted', 'refused']
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s == 'all' ? 'Toutes les saisies' : _label(s),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (s) => setState(() => _filter = s ?? 'all'),
              ),
            ),
            SwitchListTile(
              value: _showPrevious,
              title: const Text('Afficher l’historique antérieur'),
              onChanged: (value) => setState(() => _showPrevious = value),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('Aucune saisie dans cette catégorie.'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = items[i];
                        final matches = widget.snapshot?.students.where(
                          (s) => s.id == e.studentId,
                        );
                        final name = matches != null && matches.isNotEmpty
                            ? matches.first.displayName
                            : e.studentId.isEmpty
                            ? 'Toute la classe'
                            : 'Élève archivé';
                        final d = e.createdAt.toLocal();
                        final date =
                            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                        final note = (e.payload['_reviewNote'] ?? '')
                            .toString();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.status == 'refused'
                                ? Icons.error_outline
                                : e.status == 'accepted'
                                ? Icons.verified_outlined
                                : Icons.schedule,
                          ),
                          title: Text('$name — ${e.displayType}'),
                          subtitle: Text(
                            '${_label(e.status)} · $date${note.isEmpty ? '' : '\nMotif : $note'}',
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _resetting ||
                          widget.coordinator.busy ||
                          _visible.isEmpty ||
                          _error != null
                      ? null
                      : _reset,
                  icon: const Icon(Icons.restart_alt),
                  label: Text(
                    _resetting ? 'Enregistrement…' : 'Remettre le suivi à zéro',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
