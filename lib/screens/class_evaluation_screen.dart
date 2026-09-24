import '../services/safe_save.dart';
import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';

class ClassEvaluationScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final SchoolClass schoolClass;
  final List<Student> students;
  final LocalStore store;
  const ClassEvaluationScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.schoolClass,
    required this.students,
    required this.store,
  });
  @override
  State<ClassEvaluationScreen> createState() => _ClassEvaluationScreenState();
}

class _ClassEvaluationScreenState extends State<ClassEvaluationScreen>
    with SafeSave<ClassEvaluationScreen> {
  DateTime date = DateTime.now();
  String subject = 'Arabe';
  final title = TextEditingController();
  final Map<String, TextEditingController> scores = {};
  final Map<String, String> scoreStatus = {};

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  String _keyForSubject() =>
      {
        'Coran': 'quran',
        'Arabe': 'arabic',
        'Aqida': 'aqida',
        'Fiqh': 'fiqh',
        'Sira': 'sira',
      }[subject] ??
      'arabic';

  Future<void> _save() => saveGuarded(_performSave);

  Future<void> _performSave() async {
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indiquer le nom du contrôle.')),
      );
      return;
    }
    final deviceId = await widget.store.getOrCreateDeviceId();
    if (!mounted) return;
    final entries = <TeacherEvent>[];
    var count = 0;
    for (final s in widget.students) {
      final st = scoreStatus[s.id] ?? '';
      final txt = scores[s.id]?.text.trim().replaceAll(',', '.') ?? '';
      final value = double.tryParse(txt);
      if (st.isEmpty && txt.isEmpty) continue;
      if (st.isEmpty && (value == null || !value.isFinite)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Note invalide pour ${s.displayName}.')),
        );
        return;
      }
      if (st.isEmpty &&
          value != null &&
          (value < 0 || value > widget.snapshot.evaluationMax)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Note invalide pour ${s.displayName}.')),
        );
        return;
      }
      final payload = <String, dynamic>{
        'date': _date(date),
        'controlTitle': title.text.trim(),
        'subject': subject,
        if (st.isNotEmpty) 'scoreStatus': st,
        if (st.isEmpty && value != null) _keyForSubject(): value,
      };
      entries.add(
        TeacherEvent.create(
          type: 'evaluation',
          teacher: widget.config.teacher,
          studentId: s.id,
          classId: widget.schoolClass.id,
          deviceId: deviceId,
          payload: payload,
        ),
      );
      count++;
    }
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aucune nouvelle saisie à enregistrer.'),
          ),
        );
      }
      return;
    }
    await widget.store.enqueueMany(entries);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$count note(s)/statut(s) enregistré(s). Elles devront être validées par le Principal.',
        ),
      ),
    );
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    title.dispose();
    for (final controller in scores.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Contrôle — ${widget.schoolClass.name}')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: title,
            decoration: const InputDecoration(labelText: 'Nom du contrôle'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: subject,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Matière'),
            items: const [
              'Coran',
              'Arabe',
              'Aqida',
              'Fiqh',
              'Sira',
            ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (v) => setState(() => subject = v ?? 'Arabe'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(DateTime.now().year - 1),
                lastDate: DateTime(DateTime.now().year + 1),
              );
              if (mounted && d != null) setState(() => date = d);
            },
            icon: const Icon(Icons.calendar_month),
            label: Text(_date(date)),
          ),
          const SizedBox(height: 16),
          ...widget.students.map((student) {
            final controller = scores.putIfAbsent(
              student.id,
              () => TextEditingController(),
            );
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: controller,
                            enabled: (scoreStatus[student.id] ?? '').isEmpty,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Note / ${widget.snapshot.evaluationMax.toStringAsFixed(0)}',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: scoreStatus[student.id] ?? '',
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'État',
                            ),
                            items: const ['', 'Absent', 'Dispensé', 'Non noté']
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(e.isEmpty ? 'Noté' : e),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(
                              () => scoreStatus[student.id] = v ?? '',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Enregistrer les notes'),
          ),
          const SizedBox(height: 30),
        ],
      ),
    ),
  );
}
