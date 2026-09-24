import 'package:uuid/uuid.dart';

class TeacherEvent {
  static const _uuid = Uuid();

  final String id;
  final String type;
  final String teacher;
  final String studentId;
  final String classId;
  final String deviceId;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String status;

  const TeacherEvent({
    required this.id,
    required this.type,
    required this.teacher,
    required this.studentId,
    required this.classId,
    this.deviceId = '',
    required this.createdAt,
    required this.payload,
    this.status = 'pending',
  });

  factory TeacherEvent.create({
    required String type,
    required String teacher,
    required String studentId,
    required String classId,
    String deviceId = '',
    required Map<String, dynamic> payload,
  }) => TeacherEvent(
    id: 'MOB-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4()}',
    type: type,
    teacher: teacher,
    studentId: studentId,
    classId: classId,
    deviceId: deviceId,
    createdAt: DateTime.now(),
    payload: payload,
  );

  factory TeacherEvent.fromJson(Map<String, dynamic> json) => TeacherEvent(
    id: (json['id'] ?? '').toString(),
    type: (json['type'] ?? json['category'] ?? '').toString(),
    teacher: (json['teacher'] ?? '').toString(),
    studentId: (json['studentId'] ?? '').toString(),
    classId: (json['classId'] ?? '').toString(),
    deviceId: (json['deviceId'] ?? '').toString(),
    createdAt:
        DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
        DateTime.now(),
    payload: json['payload'] is Map
        ? Map<String, dynamic>.from(json['payload'])
        : <String, dynamic>{},
    status: (json['_mobileStatus'] ?? 'pending').toString(),
  );

  bool get supportedByPrincipal => const {
    'attendance',
    'evaluation',
    'communication',
    'quranValidation',
    'quran_validation',
    'quranProgress',
    'quran_progress',
    'homework',
    'lessonFollowUp',
    'lesson_follow_up',
    'annualAppreciation',
    'annual_appreciation',
  }.contains(type);

  String get protocolType {
    if (type == 'quranValidation') return 'quran_validation';
    if (type == 'quranProgress') return 'quran_progress';
    if (type == 'lessonFollowUp') return 'lesson_follow_up';
    if (type == 'annualAppreciation') return 'annual_appreciation';
    return type;
  }

  String get displayType {
    switch (protocolType) {
      case 'attendance':
        return (payload['status'] ?? 'Assiduité').toString();
      case 'evaluation':
        return 'Évaluation';
      case 'communication':
        return (payload['category'] ?? 'Message / incident').toString();
      case 'quran_validation':
        return '${payload['kind'] ?? 'Coran'} validé';
      case 'quran_progress':
        return 'Progression Coran';
      case 'homework':
        return 'Devoir / consigne';
      case 'lesson_follow_up':
        return 'Suivi de leçon';
      case 'annual_appreciation':
        return 'Appréciation annuelle';
      default:
        return protocolType;
    }
  }

  String get unsupportedLabel => displayType;

  Map<String, dynamic> toProtocolV6Json() {
    final result = <String, dynamic>{
      'id': id,
      'teacher': teacher,
      'type': protocolType,
      'studentId': studentId,
      'classId': classId,
      if (deviceId.isNotEmpty) 'deviceId': deviceId,
      'createdAt': createdAt.toIso8601String(),
    };

    switch (protocolType) {
      case 'attendance':
        result['attendance'] = payload;
        break;
      case 'evaluation':
        result['evaluation'] = payload;
        break;
      case 'communication':
        result['communication'] = payload;
        break;
      case 'quran_validation':
        result['quranValidation'] = payload;
        break;
      case 'quran_progress':
        result['quranProgress'] = payload;
        break;
      case 'homework':
        result['homework'] = payload;
        break;
      case 'lesson_follow_up':
        result['lessonFollowUp'] = payload;
        break;
      case 'annual_appreciation':
        result['annualAppreciation'] = payload;
        break;
      default:
        result['payload'] = payload;
    }
    return result;
  }

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'type': type,
    'teacher': teacher,
    'studentId': studentId,
    'classId': classId,
    'deviceId': deviceId,
    'createdAt': createdAt.toIso8601String(),
    'payload': payload,
    '_mobileStatus': status,
  };

  TeacherEvent copyWithStatus(String newStatus, {String? reviewNote}) {
    final nextPayload = Map<String, dynamic>.from(payload);
    if (reviewNote != null) {
      if (reviewNote.trim().isEmpty) {
        nextPayload.remove('_reviewNote');
      } else {
        nextPayload['_reviewNote'] = reviewNote.trim();
      }
    }
    return TeacherEvent(
      id: id,
      type: type,
      teacher: teacher,
      studentId: studentId,
      classId: classId,
      deviceId: deviceId,
      createdAt: createdAt,
      payload: nextPayload,
      status: newStatus,
    );
  }
}
