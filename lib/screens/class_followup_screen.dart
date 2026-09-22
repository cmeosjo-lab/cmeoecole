import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/reference_data.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../widgets/save_guard.dart';

class ClassFollowUpScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final SchoolClass schoolClass;
  final List<Student> students;
  final LocalStore store;
  const ClassFollowUpScreen({super.key, required this.config, required this.snapshot,
    required this.schoolClass, required this.students, required this.store});
  @override
  State<ClassFollowUpScreen> createState() => _ClassFollowUpScreenState();
}

class _ClassFollowUpScreenState extends State<ClassFollowUpScreen> with SaveGuard<ClassFollowUpScreen> {
  ReferenceItem? lesson;
  final states = <String, String>{};
  static const statuses = ['Fait', 'Non fait', 'Fait partiellement', 'Vérifié', 'Reporté'];
  Future<void> save() => runSave(() async {
    if (lesson == null) return;
    final device = await widget.store.getOrCreateDeviceId();
    final revisions = <String, int>{};
    final previous = lesson!.raw['followUps'];
    if (previous is List) {
      for (final item in previous.whereType<Map>()) {
        revisions['${item['studentId']}'] = int.tryParse('${item['revision'] ?? 0}') ?? 0;
      }
    }
    final additions = widget.students.map((student) => TeacherEvent.create(
      type: 'lesson_followup', teacher: widget.config.teacher, studentId: student.id,
      classId: widget.schoolClass.id, deviceId: device,
      payload: {'lessonId': lesson!.id, 'lesson': lesson!.label,
        'status': states[student.id] ?? 'Fait', 'baseRevision': revisions[student.id] ?? 0},
    )).toList();
    await widget.store.enqueueAll(additions);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${additions.length} suivis enregistrés. Synchronisez pour les transmettre au Principal.')));
    Navigator.pop(context, true);
  });
  @override
  Widget build(BuildContext context) {
    final lessons = widget.snapshot.references.lessons.where((e) => e.raw['classId'] == widget.schoolClass.id).toList();
    return Scaffold(appBar: AppBar(title: Text('Suivi — ${widget.schoolClass.name}')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: DropdownButtonFormField<ReferenceItem>(
          initialValue: lesson, isExpanded: true, decoration: const InputDecoration(labelText: 'Leçon / devoir'),
          items: lessons.map((e) => DropdownMenuItem(value: e, child: Text(e.displayLabel, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: saving ? null : (e) => setState(() { lesson = e; states.clear(); }),
        )),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(lessons.isEmpty
          ? 'Aucune leçon reçue pour cette classe. Synchronisez avec le Principal V2.3.'
          : 'Fait pour tous par défaut. Modifiez les exceptions avant d’enregistrer.')),
        Expanded(child: ListView.builder(itemCount: widget.students.length, itemBuilder: (context, i) {
          final student = widget.students[i];
          return ListTile(title: Text(student.displayName), trailing: DropdownButton<String>(
            value: states[student.id] ?? 'Fait',
            items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: saving ? null : (s) => setState(() => states[student.id] = s ?? 'Fait'),
          ));
        })),
        Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
          onPressed: saving || lesson == null ? null : save, icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer la classe'),
        )),
      ])),
    );
  }
}
