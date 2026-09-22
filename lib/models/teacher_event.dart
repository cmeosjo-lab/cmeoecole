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
  final String reviewNote;
  final String reviewedAt;

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
    this.reviewNote = '',
    this.reviewedAt = '',
  });

  factory TeacherEvent.create({
    required String type,
    required String teacher,
    required String studentId,
    required String classId,
    String deviceId = '',
    required Map<String, dynamic> payload,
  }) =>
      TeacherEvent(
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
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ?? DateTime.now(),
        payload: json['payload'] is Map ? Map<String, dynamic>.from(json['payload']) : <String, dynamic>{},
        status: (json['_mobileStatus'] ?? 'pending').toString(),
        reviewNote: (json['reviewNote'] ?? '').toString(),
        reviewedAt: (json['reviewedAt'] ?? '').toString(),
      );

  bool get supportedByPrincipal => const {
        'attendance',
        'quran_progress',
        'lesson_followup',
        'lessonFollowUp',
        'evaluation',
        'communication',
        'quranValidation',
        'quran_validation',
        'homework',
        'annualAppreciation',
        'annual_appreciation',
      }.contains(type);

  String get protocolType {
    if (type == 'lessonFollowUp') return 'lesson_followup';
    if (type == 'quranValidation') return 'quran_validation';
    if (type == 'annualAppreciation') return 'annual_appreciation';
    return type;
  }

  String get unsupportedLabel {
    if (type == 'lessonFollowUp') return 'suivi de leçon';
    return type;
  }

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
      case 'quran_progress':
        result['quranProgress'] = payload;
        break;
      case 'lesson_followup':
        final date = '${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';
        result['lessonFollowUp'] = {'date': date, ...payload};
        break;
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
      case 'homework':
        result['homework'] = payload;
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
        'reviewNote': reviewNote,
        'reviewedAt': reviewedAt,
      };

  TeacherEvent copyWithStatus(String newStatus, {String? note, String? reviewedAt}) => TeacherEvent(
        id: id,
        type: type,
        teacher: teacher,
        studentId: studentId,
        classId: classId,
        deviceId: deviceId,
        createdAt: createdAt,
        payload: payload,
        status: newStatus,
        reviewNote: note ?? reviewNote,
        reviewedAt: reviewedAt ?? this.reviewedAt,
      );
}
