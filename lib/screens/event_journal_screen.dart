import 'package:flutter/material.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class EventJournalScreen extends StatefulWidget {
  final LocalStore store;
  final SyncSnapshot? snapshot;
  const EventJournalScreen({super.key, required this.store, this.snapshot});
  @override
  State<EventJournalScreen> createState() => _EventJournalScreenState();
}

class _EventJournalScreenState extends State<EventJournalScreen> {
  List<TeacherEvent> events = [];
  String filter = '';
  String? error;
  static const labels = {'pending': 'À envoyer', 'received': 'Reçu, à valider',
    'accepted': 'Validé', 'refused': 'Refusé', 'error': 'À corriger'};
  static const fieldLabels = {'date': 'Date', 'status': 'État', 'note': 'Observation', 'lesson': 'Leçon', 'subject': 'Matière', 'surah': 'Sourate', 'verseFrom': 'Du verset', 'verseTo': 'Au verset', 'justified': 'Justifié', 'arrivalTime': 'Arrivée', 'controlTitle': 'Contrôle', 'scoreStatus': 'État de la note', 'title': 'Titre', 'message': 'Message', 'category': 'Nature', 'priority': 'Priorité', 'quran': 'Coran', 'arabic': 'Arabe', 'aqida': 'Aqida', 'fiqh': 'Fiqh', 'sira': 'Sira', 'hizb': 'Hizb', 'juz': 'Juz'};
  static const types = {'attendance': 'Présence', 'evaluation': 'Évaluation',
    'communication': 'Observation', 'homework': 'Devoir', 'lesson_followup': 'Suivi de leçon',
    'quran_progress': 'Sourate / versets', 'quran_validation': 'Hizb / Juz',
    'annual_appreciation': 'Appréciation'};
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    try {
      final all = await widget.store.loadAllEvents();
      all.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted) setState(() { events = all; error = null; });
    } catch (e) { if (mounted) setState(() => error = '$e'); }
  }
  String name(TeacherEvent event) {
    for (final student in widget.snapshot?.students ?? <Student>[]) {
      if (student.id == event.studentId) return student.displayName;
    }
    return event.studentId.isEmpty ? 'Classe ${event.classId}' : event.studentId;
  }
  @override
  Widget build(BuildContext context) {
    final shown = events.where((e) => filter.isEmpty || e.status == filter).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Journal des saisies')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<String>(
          initialValue: filter,
          decoration: const InputDecoration(labelText: 'État'),
          items: [const DropdownMenuItem(value: '', child: Text('Tous les états')),
            ...labels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))],
          onChanged: (value) => setState(() => filter = value ?? ''),
        )),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        Expanded(child: RefreshIndicator(onRefresh: refresh, child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: shown.isEmpty ? 1 : shown.length,
          itemBuilder: (context, i) {
            if (shown.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Text('Aucune saisie dans cet état.'));
            final event = shown[i];
            final date = event.createdAt.toLocal().toString().substring(0, 16);
            return ExpansionTile(
              title: Text('${types[event.protocolType] ?? event.type} — ${name(event)}'),
              subtitle: Text('$date · ${labels[event.status] ?? event.status}'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...event.payload.entries.where((e) => !const ['baseRevision', 'lessonId', 'lessonNumber'].contains(e.key)).map((e) => Text('${fieldLabels[e.key] ?? e.key} : ${e.value}')),
                if (event.reviewNote.isNotEmpty) Text('Retour du Principal : ${event.reviewNote}'),
                if (event.reviewedAt.isNotEmpty) Text('Examiné le ${event.reviewedAt}'),
                if (event.status == 'error') TextButton(onPressed: () async {
                  try { await widget.store.retryEvent(event.id); await refresh(); }
                  catch (e) { if (mounted) setState(() => error = '$e'); }
                }, child: const Text('Réessayer après correction sur le Principal')),
                if (event.status == 'refused') const Text('Saisie conservée. Consultez le motif avant de créer une nouvelle saisie corrigée.'),
              ],
            );
          },
        ))),
      ])),
    );
  }
}
