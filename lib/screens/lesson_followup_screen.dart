import '../services/safe_save.dart';
import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/reference_data.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class LessonFollowUpScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final Student student;
  final LocalStore store;
  const LessonFollowUpScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.student,
    required this.store,
  });

  @override
  State<LessonFollowUpScreen> createState() => _LessonFollowUpScreenState();
}

class _LessonFollowUpScreenState extends State<LessonFollowUpScreen>
    with SafeSave<LessonFollowUpScreen> {
  String? subject;
  ReferenceItem? lesson;
  String status = 'Fait';
  final note = TextEditingController();

  String _today() {
    final d = DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year.toString().padLeft(4, '0')}';
  }

  Future<void> save() => saveGuarded(_performSave);

  Future<void> _performSave() async {
    if (lesson == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choisir une leçon.')));
      return;
    }
    final deviceId = await widget.store.getOrCreateDeviceId();
    final event = TeacherEvent.create(
      type: 'lesson_follow_up',
      teacher: widget.config.teacher,
      studentId: widget.student.id,
      classId: widget.student.classId,
      deviceId: deviceId,
      payload: {
        'date': _today(),
        'lessonId': lesson!.id,
        'lesson': lesson!.label,
        if (lesson!.number > 0) 'lessonNumber': lesson!.number,
        if (lesson!.subject.isNotEmpty) 'subject': lesson!.subject,
        'status': status,
        if (note.text.trim().isNotEmpty) 'note': note.text.trim(),
      },
    );
    await widget.store.enqueue(event);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Suivi de leçon enregistré. Synchroniser pour l’envoyer au Principal.',
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
    final allLessons = widget.snapshot.references.lessons.where((e) {
      final classId = (e.raw['classId'] ?? '').toString().trim();
      return classId.isEmpty || classId == widget.student.classId;
    }).toList();
    final subjects =
        allLessons
            .map((e) => e.subject.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final lessons = subject == null || subject!.isEmpty
        ? allLessons
        : allLessons.where((e) => e.subject.trim() == subject).toList();
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
              'Suivi de leçon — ${widget.student.displayName}',
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
                'Le suivi est transmis au Principal, où il reste soumis à validation avant intégration au suivi de la leçon.',
              ),
            ),
            const SizedBox(height: 16),
            if (subjects.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: subject,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Matière'),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('Toutes les matières'),
                  ),
                  ...subjects.map(
                    (e) => DropdownMenuItem<String>(value: e, child: Text(e)),
                  ),
                ],
                onChanged: (v) => setState(() {
                  subject = (v == null || v.isEmpty) ? null : v;
                  lesson = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<ReferenceItem>(
              initialValue: lesson,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Leçon'),
              items: lessons.map((e) {
                final date = (e.raw['date'] ?? '').toString().trim();
                final prefix = [
                  date,
                  e.subject,
                ].where((x) => x.trim().isNotEmpty).join(' — ');
                return DropdownMenuItem(
                  value: e,
                  child: Text(
                    '${prefix.isEmpty ? '' : '$prefix — '}${e.displayLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: lessons.isEmpty
                  ? null
                  : (v) => setState(() => lesson = v),
            ),
            if (lessons.isEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Aucune leçon de cette classe n’a été reçue du PC Principal. Synchronisez après avoir créé les leçons côté Principal.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'État'),
              items: const [
                DropdownMenuItem(value: 'Fait', child: Text('Fait')),
                DropdownMenuItem(value: 'Vérifié', child: Text('Vérifié')),
                DropdownMenuItem(
                  value: 'Fait partiellement',
                  child: Text('Fait partiellement'),
                ),
                DropdownMenuItem(value: 'Non fait', child: Text('Non fait')),
                DropdownMenuItem(value: 'Reporté', child: Text('Reporté')),
                DropdownMenuItem(
                  value: 'À renseigner',
                  child: Text('À renseigner'),
                ),
              ],
              onChanged: (v) => setState(() => status = v ?? 'Fait'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observation facultative',
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: lessons.isEmpty ? null : save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
