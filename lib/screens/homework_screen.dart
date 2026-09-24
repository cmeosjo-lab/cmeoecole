import 'package:flutter/material.dart';
import '../models/principal_config.dart';
import '../models/reference_data.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';
import '../services/local_store.dart';
import '../services/safe_save.dart';

class HomeworkScreen extends StatefulWidget {
  final PrincipalConfig config;
  final SyncSnapshot snapshot;
  final SchoolClass schoolClass;
  final LocalStore store;
  const HomeworkScreen({super.key,required this.config,required this.snapshot,required this.schoolClass,required this.store});
  @override State<HomeworkScreen> createState()=>_HomeworkScreenState();
}
class _HomeworkScreenState extends State<HomeworkScreen> with SafeSave<HomeworkScreen> {
  DateTime date=DateTime.now();
  String subject='Arabe';
  final lessonNumbers=TextEditingController(),exerciseNumbers=TextEditingController(),manualText=TextEditingController();
  final learn=<Map<String,dynamic>>[],review=<Map<String,dynamic>>[];
  String _date(DateTime d)=>'${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
  @override void dispose(){lessonNumbers.dispose();exerciseNumbers.dispose();manualText.dispose();super.dispose();}
  Future<void> _addRange(bool learning) async {
    ReferenceItem? surah; int from=1,to=1;
    final result=await showDialog<Map<String,dynamic>>(context:context,builder:(outer)=>StatefulBuilder(builder:(context,update)=>AlertDialog(
      title:Text(learning?'À apprendre':'À réviser'),
      content:SizedBox(width:450,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<ReferenceItem>(isExpanded:true,initialValue:surah,decoration:const InputDecoration(labelText:'Sourate'),
          items:widget.snapshot.references.surahs.where((e)=>e.verseCount>0).map((e)=>DropdownMenuItem(value:e,child:Text(e.displayLabel,overflow:TextOverflow.ellipsis))).toList(),
          onChanged:(v)=>update((){surah=v;from=1;to=1;})),
        if(surah!=null)...[
          const SizedBox(height:12),
          DropdownButtonFormField<int>(key:ValueKey('from-${surah!.id}'),initialValue:from,isExpanded:true,decoration:const InputDecoration(labelText:'Premier verset'),
            items:List.generate(surah!.verseCount,(i)=>DropdownMenuItem(value:i+1,child:Text('${i+1}'))),
            onChanged:(v)=>update((){from=v??1;if(to<from)to=from;})),
          const SizedBox(height:12),
          DropdownButtonFormField<int>(key:ValueKey('to-${surah!.id}-$from-$to'),initialValue:to,isExpanded:true,decoration:const InputDecoration(labelText:'Dernier verset'),
            items:List.generate(surah!.verseCount-from+1,(i)=>DropdownMenuItem(value:from+i,child:Text('${from+i}'))),onChanged:(v)=>update(()=>to=v??from)),
        ],
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(outer),child:const Text('Annuler')),
        FilledButton(onPressed:surah==null?null:()=>Navigator.pop(outer,{'surah':surah!.label,'from':from,'to':to}),child:const Text('Ajouter'))],
    )));
    if(result!=null&&mounted)setState(()=>(learning?learn:review).add(result));
  }
  Future<void> _save()=>saveGuarded(()async{
    final quran=subject=='Coran';
    final hasText=manualText.text.trim().isNotEmpty;
    if(!hasText&&(quran?learn.isEmpty&&review.isEmpty:lessonNumbers.text.trim().isEmpty&&exerciseNumbers.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ajoutez une consigne, une leçon, un exercice ou une plage de versets.')));return;
    }
    final device=await widget.store.getOrCreateDeviceId();
    await widget.store.enqueue(TeacherEvent.create(type:'homework',teacher:widget.config.teacher,studentId:'',classId:widget.schoolClass.id,deviceId:device,payload:{
      'date':_date(date),'audience':'Classe',
      if(!quran)'book':subject,
      if(!quran&&lessonNumbers.text.trim().isNotEmpty)'lessonNumbers':lessonNumbers.text.trim(),
      if(!quran&&exerciseNumbers.text.trim().isNotEmpty)'exerciseNumbers':exerciseNumbers.text.trim(),
      if(quran&&learn.isNotEmpty)'learnRanges':learn,
      if(quran&&review.isNotEmpty)'reviewRanges':review,
      if(hasText)'manualText':manualText.text.trim(),
    }));
    if(!mounted)return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Devoir enregistré. Envoi automatique dès que le Principal est disponible.')));
    Navigator.pop(context,true);
  });
  Widget _ranges(String title,List<Map<String,dynamic>> items,bool learning)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:Theme.of(context).textTheme.titleMedium),
    ...items.asMap().entries.map((e)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${e.value['surah']} : ${e.value['from']}–${e.value['to']}'),
      trailing:IconButton(tooltip:'Retirer cette plage',icon:const Icon(Icons.close),onPressed:()=>setState(()=>items.removeAt(e.key))))),
    OutlinedButton.icon(onPressed:widget.snapshot.references.surahs.isEmpty?null:()=>_addRange(learning),icon:const Icon(Icons.add),label:const Text('Ajouter une plage de versets')),
    const SizedBox(height:16),
  ]);
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Devoir — ${widget.schoolClass.name}')),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
      InkWell(onTap:()async{final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime(DateTime.now().year-1),lastDate:DateTime(DateTime.now().year+1));if(mounted&&d!=null)setState(()=>date=d);},
        child:InputDecorator(decoration:const InputDecoration(labelText:'Date'),child:Text(_date(date)))),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(initialValue:subject,decoration:const InputDecoration(labelText:'Matière'),
        items:const ['Arabe','Aqida','Fiqh','Sira','Tajwid','Coran'].map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>setState(()=>subject=v??'Arabe')),
      const SizedBox(height:16),
      if(subject=='Coran')...[
        _ranges('À apprendre',learn,true),_ranges('À réviser',review,false),
        if(widget.snapshot.references.surahs.isEmpty)const Text('Synchronisez le référentiel pour choisir des sourates.'),
      ] else ...[
        TextField(controller:lessonNumbers,decoration:const InputDecoration(labelText:'Leçon(s) n°')),
        const SizedBox(height:10),TextField(controller:exerciseNumbers,decoration:const InputDecoration(labelText:'Exercice(s) n°')),
      ],
      const SizedBox(height:12),TextField(controller:manualText,maxLines:4,maxLength:4000,decoration:const InputDecoration(labelText:'Consigne complémentaire')),
      const SizedBox(height:20),FilledButton.icon(onPressed:saving?null:_save,icon:const Icon(Icons.save_outlined),label:const Text('Enregistrer pour validation')),
      const SizedBox(height:30),
    ])));
}
