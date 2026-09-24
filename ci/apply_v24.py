"""One-time migration of unchanged V0.5.6 screens. No real school data is used."""
from pathlib import Path
import re

M=Path('.')
marker=M/'ci/V24_MIGRATED'
if marker.exists():
    raise SystemExit(0)
p=M/'pubspec.yaml';s=p.read_text().replace('0.5.6+13','0.6.0+14')
s=s.replace('dependencies:\n','dependencies:\n  sqflite: ^2.4.4\n',1)
s=s.replace('dev_dependencies:\n','dev_dependencies:\n  sqflite_common_ffi: ^2.3.6\n')
p.write_text(s)
p=M/'lib/services/principal_api.dart';s="import 'dart:async';\n"+p.read_text().replace("mobileVersion = '0.5.6'","mobileVersion = '0.6.0'")
s=s.replace("'teacher': c.teacher,","'teacher': c.teacher,\n        if (c.principalId.isNotEmpty) 'principalId': c.principalId,")
s=s.replace('if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;',"if (r.statusCode == 403) throw PrincipalApiException('Code professeur incorrect ou accès désactivé dans le Principal.');\n      if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw PrincipalApiException('Le Principal répond, mais l’appairage a échoué (${r.statusCode}).');",1)
s=s.replace('if (!ok || protocol != supportedProtocol || teacher.isEmpty) return null;',"if (protocol != supportedProtocol) throw PrincipalApiException('Versions incompatibles. Mettez à jour le Principal et le mobile ensemble.');\n      if (!ok || teacher.isEmpty) throw PrincipalApiException('Réponse du Principal invalide.');")
s=s.replace('Cet appareil est désactivé dans le Principal. Réactivez-le dans Réseau enseignants > Appareils autorisés.','Cet appareil attend une autorisation ou est désactivé. Sur le Principal : Réseau enseignants > Appareils autorisés.')
s=s.replace('code: code,\n      );',"code: code,\n        principalId: (data['principalId'] ?? '').toString(),\n      );",1)
s=s.replace('''} on PrincipalApiException {
      rethrow;
    } catch (_) {
      return null;
    }''','''} on PrincipalApiException { rethrow; }
    on TimeoutException { throw PrincipalApiException('Le PC Principal ne répond pas. Vérifiez le Wi-Fi, son adresse et le pare-feu Windows.'); }
    on SocketException { throw PrincipalApiException('Réseau local inaccessible. Vérifiez le Wi-Fi et l’autorisation Réseau local.'); }
    on FormatException { throw PrincipalApiException('La réponse reçue n’est pas une réponse GESTCOURS valide.'); }''',1)
a=s.index('    final host = rawHost.trim()');b=s.index('    final code = rawCode.trim()',a)
s=s[:a]+'''    final raw = rawHost.trim();
    final parsed = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (parsed == null || parsed.scheme != 'http' || parsed.host.isEmpty || parsed.userInfo.isNotEmpty) {
      throw PrincipalApiException('Adresse invalide. Exemple : 192.168.1.20 ou 192.168.1.20:47831.');
    }
    final host = parsed.host;
    final port = parsed.hasPort ? parsed.port : defaultPort;
    if (port < 1 || port > 65535) throw PrincipalApiException('Le numéro de port est invalide.');
'''+s[b:]
s=s.replace('deviceId: deviceId, port: defaultPort, pairTimeout:', 'deviceId: deviceId, port: port, pairTimeout:').replace('Connexion impossible à $host:$defaultPort.', 'Connexion impossible à $host:$port.')
s=s.replace('if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) return const {};',"if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) throw PrincipalApiException('Les décisions du Principal ne sont pas disponibles (${r.statusCode}).');")
p.write_text(s)
p=M/'lib/screens/setup_screen.dart';s=p.read_text().replace('await widget.store.saveConfig(c);\n      await widget.store.saveSnapshot(snapshot);','await widget.store.activateSession(c, snapshot);').replace('if (result == null) return;','if (result == null || !mounted) return;');p.write_text(s)
p=M/'lib/screens/roll_call_screen.dart';s=p.read_text().replace('final deviceId = await widget.store.getOrCreateDeviceId();','final deviceId = await widget.store.getOrCreateDeviceId();\n    if (!mounted) return;\n    final entries = <TeacherEvent>[];')
s=s.replace('await widget.store.enqueue(TeacherEvent.create(', 'entries.add(TeacherEvent.create(')
s=s.replace('    if (!mounted) return;\n    ScaffoldMessenger',"    if (entries.isEmpty) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune nouvelle saisie à enregistrer.'))); return; }\n    await widget.store.enqueueMany(entries);\n    if (!mounted) return;\n    ScaffoldMessenger")
p.write_text(s)
p=M/'lib/screens/quran_screen.dart';s=p.read_text().replace('    var created = 0;','    final entries = <TeacherEvent>[];\n    var created = 0;')
s=s.replace('await widget.store.enqueue(TeacherEvent.create(', 'entries.add(TeacherEvent.create(').replace('    if (!mounted) return;\n    ScaffoldMessenger','    await widget.store.enqueueMany(entries);\n    if (!mounted) return;\n    ScaffoldMessenger')
s=s.replace('if (surah != null && (verseFrom == null || verseTo == null) && !hasValidation)','if (surah != null && (verseFrom == null || verseTo == null))');p.write_text(s)
p=M/'lib/screens/incident_screen.dart';s=p.read_text()
s=s.replace('final base = List<String>.from(builtIn[family] ?? const <String>[]);',"final refs = widget.snapshot.raw['referenceData'];\n    final families = refs is Map ? refs['incidentFamilies'] : null;\n    final remote = families is Map ? families[family] : null;\n    final base = remote is List ? remote.map((e)=>e.toString()).toList() : List<String>.from(builtIn[family] ?? const <String>[]);")
s=s.replace('List<String> get remarkChoices => List<String>.from(remarks[nature] ?? const <String>[]);',"List<String> get remarkChoices {\n    final refs=widget.snapshot.raw['referenceData'];\n    final presets=refs is Map ? refs['incidentRemarks'] : null;\n    final remote=presets is Map ? presets[nature] : null;\n    return remote is List ? remote.map((e)=>e.toString()).toList() : List<String>.from(remarks[nature] ?? const <String>[]);\n  }")
p.write_text(s)
p=M/'lib/screens/classes_screen.dart';s="import 'class_lesson_screen.dart';\n"+p.read_text()
s=s.replace('HomeworkScreen(config: config, schoolClass:', 'HomeworkScreen(config: config, snapshot: snapshot, schoolClass:')
s=s.replace("icon: const Icon(Icons.assignment_outlined), label: const Text('Devoir')),", "icon: const Icon(Icons.assignment_outlined), label: const Text('Devoir')),\n                      OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>ClassLessonScreen(config:config,snapshot:snapshot,schoolClass:schoolClass,students:students,store:store))),icon:const Icon(Icons.menu_book),label:const Text('Suivi de leçon')),")
s=s.replace('appBar: AppBar(title: Text(className)),',"appBar: AppBar(title: Text(className),actions:[IconButton(tooltip:'Rechercher un élève',icon:const Icon(Icons.search),onPressed:()async{\n        final selected=await showSearch<Student?>(context:context,delegate:_StudentSearch(students));\n        if(selected!=null&&context.mounted)Navigator.push(context,MaterialPageRoute(builder:(_)=>StudentScreen(config:config,snapshot:snapshot,student:selected,store:store)));\n      })]),")
s+='''
class _StudentSearch extends SearchDelegate<Student?> {
  final List<Student> students;
  _StudentSearch(this.students):super(searchFieldLabel:'Nom ou prénom');
  @override List<Widget> buildActions(BuildContext context)=>[IconButton(tooltip:'Effacer',onPressed:()=>query='',icon:const Icon(Icons.clear))];
  @override Widget buildLeading(BuildContext context)=>IconButton(tooltip:'Retour',onPressed:()=>close(context,null),icon:const Icon(Icons.arrow_back));
  Widget _results(BuildContext context){
    final hits=students.where((s)=>s.displayName.toLowerCase().contains(query.trim().toLowerCase())).toList();
    return hits.isEmpty?const Center(child:Text('Aucun élève correspondant.')):ListView.builder(itemCount:hits.length,itemBuilder:(context,i)=>ListTile(title:Text(hits[i].displayName),onTap:()=>close(context,hits[i])));
  }
  @override Widget buildResults(BuildContext context)=>_results(context);
  @override Widget buildSuggestions(BuildContext context)=>_results(context);
}
''';p.write_text(s)
for p in (M/'lib/screens').glob('*.dart'):
    s=p.read_text();names=re.findall(r'final\s+(\w+)\s*=\s*TextEditingController\(',s)
    if p.name=='home_screen.dart':names=[]
    if names and 'void dispose()' not in s:
        choices=['\n  @override\n  Widget build','\n  @override Widget build','\n  @override\n  void initState']
        pos=next(s.index(k) for k in choices if k in s)
        extra='\n    for (final controller in scores.values) { controller.dispose(); }' if 'Map<String, TextEditingController> scores' in s else ''
        s=s[:pos]+'\n  @override\n  void dispose() {\n    '+'\n    '.join(c+'.dispose();' for c in names)+extra+'\n    super.dispose();\n  }\n'+s[pos:]
    if 'Future<void> save() async' in s or 'Future<void> _save() async' in s:
        s="import '../services/safe_save.dart';\n"+s
        s=re.sub(r'(class _\w+State extends State<(\w+)>)( \{)',r'\1 with SafeSave<\2>\3',s)
        name='_save' if 'Future<void> _save() async' in s else 'save'
        s=s.replace(f'Future<void> {name}() async',f'Future<void> {name}() => saveGuarded(_performSave);\n\n  Future<void> _performSave() async',1)
        s=s.replace(f'onPressed: {name},',f'onPressed: saving ? null : {name},').replace(f'onPressed:{name},',f'onPressed:saving ? null : {name},')
    s=s.replace('if (d != null) setState','if (mounted && d != null) setState').replace('if(d!=null)setState','if(mounted && d!=null)setState').replace('if (t != null) setState','if (mounted && t != null) setState')
    p.write_text(s)
marker.write_text('Sources V0.6.0 / pack V2.4.0 prepared; build validation is reported separately.\n')
