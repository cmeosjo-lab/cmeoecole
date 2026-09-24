import 'class_lesson_screen.dart';
import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../services/local_store.dart';
import 'student_screen.dart';
import 'roll_call_screen.dart';
import 'homework_screen.dart';
import 'class_evaluation_screen.dart';

class ClassesScreen extends StatelessWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final LocalStore store;
  const ClassesScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.store,
  });

  List<Student> _studentsFor(SchoolClass c) =>
      snapshot.students
          .where((s) => s.classId == c.id || c.studentIds.contains(s.id))
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(snapshot.displayTitle)),
    body: SafeArea(
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          48 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount: snapshot.classes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final c = snapshot.classes[i];
          final students = _studentsFor(c);
          final className = c.name.trim().isEmpty ? 'Classe' : c.name.trim();
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2F0EC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.school_outlined,
                  color: Color(0xFF21685F),
                ),
              ),
              title: Text(
                className,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              subtitle: Text('${students.length} élève(s)'),
              trailing: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F4F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.chevron_right, size: 20),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClassStudentsScreen(
                    config: config,
                    snapshot: snapshot,
                    schoolClass: c,
                    students: students,
                    store: store,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class ClassStudentsScreen extends StatelessWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final SchoolClass schoolClass;
  final List<Student> students;
  final LocalStore store;

  const ClassStudentsScreen({
    super.key,
    required this.config,
    required this.snapshot,
    required this.schoolClass,
    required this.students,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final className = schoolClass.name.trim().isEmpty
        ? 'Classe'
        : schoolClass.name.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(className),
        actions: [
          IconButton(
            tooltip: 'Rechercher un élève',
            icon: const Icon(Icons.search),
            onPressed: () async {
              final selected = await showSearch<Student?>(
                context: context,
                delegate: _StudentSearch(students),
              );
              if (selected != null && context.mounted)
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentScreen(
                      config: config,
                      snapshot: snapshot,
                      student: selected,
                      store: store,
                    ),
                  ),
                );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: students.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucun élève reçu pour cette classe.'),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RollCallScreen(
                                config: config,
                                snapshot: snapshot,
                                schoolClass: schoolClass,
                                students: students,
                                store: store,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.fact_check_outlined),
                          label: const Text('Appel de classe'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClassEvaluationScreen(
                                config: config,
                                snapshot: snapshot,
                                schoolClass: schoolClass,
                                students: students,
                                store: store,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.grading_outlined),
                          label: const Text('Contrôle / notes'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HomeworkScreen(
                                config: config,
                                snapshot: snapshot,
                                schoolClass: schoolClass,
                                store: store,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.assignment_outlined),
                          label: const Text('Devoir'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClassLessonScreen(
                                config: config,
                                snapshot: snapshot,
                                schoolClass: schoolClass,
                                students: students,
                                store: store,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.menu_book),
                          label: const Text('Suivi de leçon'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        12,
                        12,
                        12,
                        48 + MediaQuery.of(context).padding.bottom,
                      ),
                      itemCount: students.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = students[i];
                        final display = s.displayName.trim().isNotEmpty
                            ? s.displayName.trim()
                            : (s.matricule.trim().isNotEmpty
                                  ? s.matricule.trim()
                                  : 'Élève');
                        return ListTile(
                          leading: CircleAvatar(child: Text('${i + 1}')),
                          title: Text(
                            display,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: s.matricule.trim().isEmpty
                              ? null
                              : Text('Matricule : ${s.matricule}'),
                          trailing: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F4F2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.chevron_right, size: 20),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StudentScreen(
                                config: config,
                                snapshot: snapshot,
                                student: s,
                                store: store,
                              ),
                            ),
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

class _StudentSearch extends SearchDelegate<Student?> {
  final List<Student> students;
  _StudentSearch(this.students) : super(searchFieldLabel: 'Nom ou prénom');
  @override
  List<Widget> buildActions(BuildContext context) => [
    IconButton(
      tooltip: 'Effacer',
      onPressed: () => query = '',
      icon: const Icon(Icons.clear),
    ),
  ];
  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: 'Retour',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );
  Widget _results(BuildContext context) {
    final hits = students
        .where(
          (s) =>
              s.displayName.toLowerCase().contains(query.trim().toLowerCase()),
        )
        .toList();
    return hits.isEmpty
        ? const Center(child: Text('Aucun élève correspondant.'))
        : ListView.builder(
            itemCount: hits.length,
            itemBuilder: (context, i) => ListTile(
              title: Text(hits[i].displayName),
              onTap: () => close(context, hits[i]),
            ),
          );
  }

  @override
  Widget buildResults(BuildContext context) => _results(context);
  @override
  Widget buildSuggestions(BuildContext context) => _results(context);
}
