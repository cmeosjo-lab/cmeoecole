import '../services/safe_save.dart';
import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/reference_data.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class QuranScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final Student student;
  final LocalStore store;
  const QuranScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.student,
    required this.store,
  });

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen> with SafeSave<QuranScreen> {
  ReferenceItem? surah;
  int? verseFrom;
  int? verseTo;
  ReferenceItem? hizb;
  ReferenceItem? juz;
  String progressMode = 'Mémorisé';
  final note = TextEditingController();

  List<int> get verses {
    final max = surah?.verseCount ?? 0;
    return max > 0 ? List<int>.generate(max, (i) => i + 1) : const [];
  }

  void onSurah(ReferenceItem? value) {
    setState(() {
      surah = value;
      verseFrom = null;
      verseTo = null;
    });
  }

  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';
  }

  Future<void> save() => saveGuarded(_performSave);

  Future<void> _performSave() async {
    final hasProgress = surah != null && verseFrom != null && verseTo != null;
    final hasValidation = hizb != null || juz != null;
    if (!hasProgress && !hasValidation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Choisissez une sourate avec une plage de versets, ou un Hizb/Juz à valider.',
          ),
        ),
      );
      return;
    }
    if (surah != null && (verseFrom == null || verseTo == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez le premier et le dernier verset.'),
        ),
      );
      return;
    }

    final deviceId = await widget.store.getOrCreateDeviceId();
    final entries = <TeacherEvent>[];
    var created = 0;
    if (hasProgress) {
      entries.add(
        TeacherEvent.create(
          type: 'quran_progress',
          teacher: widget.config.teacher,
          studentId: widget.student.id,
          classId: widget.student.classId,
          deviceId: deviceId,
          payload: {
            'date': _today(),
            'mode': progressMode,
            'surah': surah!.label,
            'surahNumber': surah!.number,
            'verseFrom': verseFrom,
            'verseTo': verseTo,
            if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
          },
        ),
      );
      created++;
    }
    if (hasValidation) {
      final chosen = hizb ?? juz!;
      final kind = hizb != null ? 'Hizb' : 'Juz';
      entries.add(
        TeacherEvent.create(
          type: 'quran_validation',
          teacher: widget.config.teacher,
          studentId: widget.student.id,
          classId: widget.student.classId,
          deviceId: deviceId,
          payload: {
            'date': _today(),
            'kind': kind,
            'number': chosen.number,
            if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
          },
        ),
      );
      created++;
    }

    await widget.store.enqueueMany(entries);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$created saisie(s) Coran enregistrée(s). Synchroniser pour les envoyer au Principal.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = widget.snapshot.references;
    return Scaffold(
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
              'Suivi Coran — ${widget.student.displayName}',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'La progression Sourate/versets et les validations Hizb/Juz sont synchronisées avec le Principal puis soumises à sa validation.',
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<ReferenceItem>(
              initialValue: surah,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Sourate'),
              items: ref.surahs
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: ref.surahs.isEmpty ? null : onSurah,
            ),
            if (surah != null && verses.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: verseFrom,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Verset de'),
                      items: verses
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) => setState(() {
                        verseFrom = v;
                        if (verseTo != null && v != null && verseTo! < v)
                          verseTo = v;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: verseTo,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Verset à'),
                      items: verses
                          .where((v) => verseFrom == null || v >= verseFrom!)
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => verseTo = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: progressMode,
                decoration: const InputDecoration(
                  labelText: 'Type de progression',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Mémorisé',
                    child: Text('Mémorisé / validé'),
                  ),
                  DropdownMenuItem(value: 'Révisé', child: Text('Révisé')),
                  DropdownMenuItem(
                    value: 'Travaillé',
                    child: Text('Lu / travaillé'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => progressMode = v ?? 'Mémorisé'),
              ),
            ],
            const SizedBox(height: 18),
            const Divider(),
            const SizedBox(height: 8),
            DropdownButtonFormField<ReferenceItem>(
              initialValue: hizb,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Hizb à valider (facultatif)',
              ),
              items: ref.hizbs
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: ref.hizbs.isEmpty
                  ? null
                  : (v) => setState(() {
                      hizb = v;
                      if (v != null) juz = null;
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ReferenceItem>(
              initialValue: juz,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Juz à valider (facultatif)',
              ),
              items: ref.juzs
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(
                        e.displayLabel,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: ref.juzs.isEmpty
                  ? null
                  : (v) => setState(() {
                      juz = v;
                      if (v != null) hizb = null;
                    }),
            ),
            if (ref.surahs.isEmpty ||
                (ref.hizbs.isEmpty && ref.juzs.isEmpty)) ...[
              const SizedBox(height: 10),
              const Text(
                'Une partie du référentiel Coran n’a pas encore été reçue. Lancez une synchronisation.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Remarque facultative',
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer le suivi Coran'),
            ),
          ],
        ),
      ),
    );
  }
}
