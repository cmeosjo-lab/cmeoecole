import 'dart:convert';

class PrincipalConfig {
  final String host;
  final int port;
  final String teacher;
  final String code;
  final String principalId;
  const PrincipalConfig({
    required this.host,
    required this.port,
    required this.teacher,
    required this.code,
    this.principalId = '',
  });
  String get baseUrl => Uri(scheme: 'http', host: host, port: port).toString();
  String get scopeKey => jsonEncode([
    principalId.isEmpty ? '${host.toLowerCase()}:$port' : principalId,
    teacher.trim().toLowerCase(),
  ]);
  PrincipalConfig withIdentity(String id) => PrincipalConfig(
    host: host,
    port: port,
    teacher: teacher,
    code: code,
    principalId: id,
  );
  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'teacher': teacher,
    'code': code,
    'principalId': principalId,
  };
  factory PrincipalConfig.fromJson(Map<String, dynamic> j) => PrincipalConfig(
    host: (j['host'] ?? '').toString(),
    port: int.tryParse((j['port'] ?? '47831').toString()) ?? 47831,
    teacher: (j['teacher'] ?? '').toString(),
    code: (j['code'] ?? '').toString(),
    principalId: (j['principalId'] ?? '').toString(),
  );
}
