import '../services/safe_save.dart';
import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class IncidentScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final Student student;
  final LocalStore store;
  const IncidentScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.student,
    required this.store,
  });

  @override
  State<IncidentScreen> createState() => _IncidentScreenState();
}

class _IncidentScreenState extends State<IncidentScreen>
    with SafeSave<IncidentScreen> {
  String family = 'Discipline';
  String? nature;
  String? presetRemark;
  String priority = 'Normal';
  final extra = TextEditingController();

  static const Map<String, List<String>> builtIn = {
    'Discipline': [
      'Bavardage',
      'Grossièreté',
      'Téléphone',
      'Bagarre',
      'Insolence',
      'Harcèlement',
    ],
    'Matériel': ['Non apporté', 'En mauvais état'],
    'Devoirs': ['Fait partiellement', 'Non fait'],
  };

  static const Map<String, List<String>> remarks = {
    'Bavardage': [
      'Bavardages répétés malgré plusieurs rappels.',
      'Perturbe le déroulement du cours par ses bavardages.',
      'Bavardage ponctuel pendant le cours.',
    ],
    'Grossièreté': [
      'Paroles déplacées envers un autre élève.',
      'Propos grossiers pendant le cours.',
      'Langage inadapté malgré un rappel.',
    ],
    'Téléphone': [
      'Utilisation du téléphone pendant le cours.',
      'Téléphone audible pendant le cours.',
      'Refus de ranger le téléphone après rappel.',
    ],
    'Bagarre': [
      'Altercation physique avec un autre élève.',
      'Coups portés lors d’une dispute.',
      'Provocation ayant entraîné une altercation.',
    ],
    'Insolence': [
      'Réponse irrespectueuse à l’adulte.',
      "Refus d'obéir à une consigne.",
      'Attitude provocatrice pendant le cours.',
    ],
    'Harcèlement': [
      'Comportement de harcèlement verbal signalé.',
      'Comportement de harcèlement physique signalé.',
      'Comportement de harcèlement numérique signalé.',
    ],
    'Non apporté': [
      'Matériel demandé non apporté.',
      'Livre ou cahier nécessaire non apporté.',
      'Mushaf non apporté.',
    ],
    'En mauvais état': [
      'Matériel apporté en mauvais état.',
      'Livre ou cahier en mauvais état.',
    ],
    'Fait partiellement': [
      'Devoir fait partiellement.',
      'Travail incomplet.',
      'Exercices réalisés seulement en partie.',
    ],
    'Non fait': [
      'Devoir non fait.',
      'Aucun travail rendu.',
      'Leçon ou exercices non préparés.',
    ],
  };

  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';
  }

  List<String> get natures {
    final refs = widget.snapshot.raw['referenceData'];
    final families = refs is Map ? refs['incidentFamilies'] : null;
    final remote = families is Map ? families[family] : null;
    final base = remote is List
        ? remote.map((e) => e.toString()).toList()
        : List<String>.from(builtIn[family] ?? const <String>[]);
    if (family == 'Autre') {
      final fromPrincipal = widget.snapshot.references.incidentTypes;
      if (fromPrincipal.isNotEmpty) base.addAll(fromPrincipal);
      if (base.isEmpty) base.add('Autre');
    }
    return base.toSet().toList();
  }

  List<String> get remarkChoices {
    final refs = widget.snapshot.raw['referenceData'];
    final presets = refs is Map ? refs['incidentRemarks'] : null;
    final remote = presets is Map ? presets[nature] : null;
    return remote is List
        ? remote.map((e) => e.toString()).toList()
        : List<String>.from(remarks[nature] ?? const <String>[]);
  }

  String get category {
    final n = (nature ?? '').trim();
    if (family == 'Discipline') return 'Discipline — $n';
    if (family == 'Matériel') return 'Matériel — $n';
    if (family == 'Devoirs') return 'Devoir — $n';
    return n.isEmpty ? 'Autre' : n;
  }

  String get finalRemark {
    final p = (presetRemark ?? '').trim();
    final e = extra.text.trim();
    if (p.isEmpty) return e;
    if (e.isEmpty) return p;
    return '$p $e';
  }

  Future<void> save() => saveGuarded(_performSave);

  Future<void> _performSave() async {
    if (nature == null || nature!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisir la nature du signalement.')),
      );
      return;
    }
    if (finalRemark.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisir une remarque ou ajouter un commentaire.'),
        ),
      );
      return;
    }
    final deviceId = await widget.store.getOrCreateDeviceId();
    final event = TeacherEvent.create(
      type: 'communication',
      teacher: widget.config.teacher,
      studentId: widget.student.id,
      classId: widget.student.classId,
      deviceId: deviceId,
      payload: {
        'date': _today(),
        'category': category,
        'subject': 'Signalement : $category',
        'priority': priority,
        'message': finalRemark,
      },
    );
    await widget.store.enqueue(event);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Signalement enregistré et placé en attente de transmission.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    extra.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(title: Text(widget.snapshot.displayTitle)),
    body: SafeArea(
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          48 +
              MediaQuery.of(context).padding.bottom +
              MediaQuery.of(context).viewInsets.bottom,
        ),
        children: [
          Text(
            'Signalement — ${widget.student.displayName}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: family,
            decoration: const InputDecoration(labelText: 'Catégorie'),
            items: const [
              'Discipline',
              'Matériel',
              'Devoirs',
              'Autre',
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() {
              family = v ?? 'Discipline';
              nature = null;
              presetRemark = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: nature,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Nature'),
            items: natures
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => setState(() {
              nature = v;
              presetRemark = null;
            }),
          ),
          if (remarkChoices.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: presetRemark,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Remarque proposée'),
              items: remarkChoices
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(e, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => presetRemark = v),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: priority,
            decoration: const InputDecoration(labelText: 'Priorité'),
            items: const [
              DropdownMenuItem(value: 'Normal', child: Text('Normale')),
              DropdownMenuItem(value: 'Important', child: Text('Importante')),
              DropdownMenuItem(value: 'Urgent', child: Text('Urgente')),
            ],
            onChanged: (v) => setState(() => priority = v ?? 'Normal'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: extra,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Complément facultatif',
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: saving ? null : save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer pour le Principal'),
          ),
        ],
      ),
    ),
  );
}
