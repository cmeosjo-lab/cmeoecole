import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/reference_data.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/safe_save.dart';

class ClassLessonScreen extends StatefulWidget {
  final PrincipalConfig config; final SyncSnapshot snapshot; final SchoolClass schoolClass;
  final List<Student> students; final LocalStore store;
  const ClassLessonScreen({super.key,required this.config,required this.snapshot,required this.schoolClass,required this.students,required this.store});
  @override State<ClassLessonScreen> createState()=>_ClassLessonScreenState();
}
class _ClassLessonScreenState extends State<ClassLessonScreen> with SafeSave<ClassLessonScreen> {
  static const statuses=['Fait','Vérifié','Fait partiellement','Non fait','Reporté'];
  ReferenceItem? lesson; String common='Fait'; final exceptions=<String,String>{};
  Future<void> _save()=>saveGuarded(()async{
    final selected=lesson;if(selected==null)return;
    final device=await widget.store.getOrCreateDeviceId(); final now=DateTime.now();
    final date='${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year}';
    final entries=widget.students.map((s)=>TeacherEvent.create(type:'lesson_follow_up',teacher:widget.config.teacher,studentId:s.id,classId:widget.schoolClass.id,deviceId:device,
      payload:{'date':date,'lessonId':selected.id,'lesson':selected.label,'subject':selected.subject,'status':exceptions[s.id]??common})).toList();
    await widget.store.enqueueMany(entries);
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('${entries.length} suivi(s) enregistrés ensemble. Envoi automatique dès que possible.')));
    Navigator.pop(context,true);
  });
  @override Widget build(BuildContext context) {
    final lessons=widget.snapshot.references.lessons.where((l)=>(l.raw['classId']??'').toString()==widget.schoolClass.id).toList();
    return Scaffold(appBar:AppBar(title:Text('Leçon — ${widget.schoolClass.name}')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Choisissez une leçon et un état commun, puis modifiez seulement les exceptions. Toutes les saisies sont enregistrées ensemble.'),const SizedBox(height:16),
      DropdownButtonFormField<ReferenceItem>(initialValue:lesson,isExpanded:true,decoration:const InputDecoration(labelText:'Leçon de cette classe'),
        items:lessons.map((l)=>DropdownMenuItem(value:l,child:Text('${l.subject} — ${l.label}',overflow:TextOverflow.ellipsis))).toList(),onChanged:(v)=>setState(()=>lesson=v)),
      if(lessons.isEmpty)const Padding(padding:EdgeInsets.only(top:8),child:Text('Aucune leçon reçue. Créez la leçon dans le Principal, puis synchronisez.')),
      const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:common,decoration:const InputDecoration(labelText:'État commun'),
        items:statuses.map((s)=>DropdownMenuItem(value:s,child:Text(s))).toList(),onChanged:(v)=>setState(()=>common=v??'Fait')),
      const SizedBox(height:16),
      ...widget.students.map((s)=>Padding(padding:const EdgeInsets.only(bottom:12),child:DropdownButtonFormField<String>(
        key:ValueKey('${s.id}-$common'),initialValue:exceptions[s.id]??'',isExpanded:true,decoration:InputDecoration(labelText:s.displayName),
        items:[DropdownMenuItem(value:'',child:Text('Comme la classe : $common')),...statuses.map((v)=>DropdownMenuItem(value:v,child:Text(v)))],
        onChanged:(v)=>setState((){if(v==null||v.isEmpty){exceptions.remove(s.id);}else{exceptions[s.id]=v;}})))),
      FilledButton.icon(onPressed:saving||lesson==null||widget.students.isEmpty?null:_save,icon:const Icon(Icons.save_outlined),label:Text('Enregistrer ${widget.students.length} suivi(s)')),
      const SizedBox(height:30),
    ])));
  }
}
