import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/principal_config.dart';
import '../models/school_data.dart';
import '../models/teacher_event.dart';

class PrincipalApiException implements Exception {
  final String message;
  PrincipalApiException(this.message);
  @override
  String toString() => message;
}

class PrincipalApi {
  static const int supportedProtocol = 6;
  static const int defaultPrincipalPort = 47831;
  final Duration timeout;

  const PrincipalApi({this.timeout = const Duration(seconds: 8)});

  Uri _uri(PrincipalConfig c, String path, [Map<String, String>? query]) =>
      Uri.parse('${c.baseUrl}$path').replace(queryParameters: query);

  Future<bool> ping(PrincipalConfig c) async {
    try {
      final r = await http.get(_uri(c, '/api/v1/ping')).timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300) return false;
      if (r.bodyBytes.isEmpty) return true;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is Map) {
        final ok = decoded['ok'];
        final version = int.tryParse((decoded['protocolVersion'] ?? '0').toString()) ?? 0;
        return ok == true && (version == 0 || version == supportedProtocol);
      }
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _cleanHost(String raw) {
    var host = raw.trim();
    host = host.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    if (host.contains('/')) host = host.split('/').first;
    if (host.contains(':')) host = host.split(':').first;
    return host.trim();
  }

  Future<PrincipalConfig> pairAddress(String rawHost, String rawCode) async {
    final host = _cleanHost(rawHost);
    final code = rawCode.trim();
    if (host.isEmpty) {
      throw PrincipalApiException('Saisissez l’adresse du PC Principal affichée dans GESTCOURS.');
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw PrincipalApiException('Saisissez le code professeur à 6 chiffres.');
    }

    try {
      final uri = Uri.parse('http://$host:$defaultPrincipalPort/api/v1/pair')
          .replace(queryParameters: {'code': code});
      final r = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 403) {
        throw PrincipalApiException('Code professeur refusé par le PC Principal.');
      }
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        throw PrincipalApiException(
          'Connexion impossible à $host:$defaultPrincipalPort. Vérifiez l’adresse affichée dans le Principal, le même Wi-Fi/réseau, le code professeur et l’autorisation Windows.',
        );
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map) {
        throw PrincipalApiException('Réponse du PC Principal invalide.');
      }
      final data = Map<String, dynamic>.from(decoded);
      final ok = data['ok'] == true;
      final version = int.tryParse((data['protocolVersion'] ?? '0').toString()) ?? 0;
      final teacher = (data['teacher'] ?? '').toString().trim();
      final returnedPort =
          int.tryParse((data['port'] ?? defaultPrincipalPort).toString()) ?? defaultPrincipalPort;
      if (!ok || version != supportedProtocol || teacher.isEmpty) {
        throw PrincipalApiException('Code professeur non reconnu ou protocole incompatible.');
      }
      return PrincipalConfig(
        host: host,
        port: returnedPort,
        teacher: teacher,
        code: code,
      );
    } on PrincipalApiException {
      rethrow;
    } catch (_) {
      throw PrincipalApiException(
        'Connexion impossible à $host:$defaultPrincipalPort. Vérifiez l’adresse affichée dans le Principal, le même Wi-Fi/réseau, le code professeur et l’autorisation Windows.',
      );
    }
  }

  Future<Map<String, dynamic>?> _referenceData(PrincipalConfig c) async {
    try {
      final r = await http.get(
        _uri(c, '/api/v1/reference-data', {'teacher': c.teacher, 'code': c.code}),
        headers: {'Accept': 'application/json', 'User-Agent': 'GESTCOURS-Prof-Mobile/0.5.4'},
      ).timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) return null;
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<SyncSnapshot> sync(PrincipalConfig c) async {
    final r = await http.get(
      _uri(c, '/api/v1/sync', {'teacher': c.teacher, 'code': c.code}),
      headers: {'Accept': 'application/json', 'User-Agent': 'GESTCOURS-Prof-Mobile/0.5.4'},
    ).timeout(timeout);

    if (r.statusCode == 403) {
      throw PrincipalApiException('PC Principal trouvé, mais le professeur ou le code est refusé.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PrincipalApiException('Synchronisation refusée (${r.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is! Map) throw PrincipalApiException('Réponse de synchronisation invalide.');
    var snapshot = SyncSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    if (snapshot.protocolVersion != 0 && snapshot.protocolVersion != supportedProtocol) {
      throw PrincipalApiException(
        'Version de protocole incompatible : Principal ${snapshot.protocolVersion}, mobile $supportedProtocol.',
      );
    }
    final references = await _referenceData(c);
    if (references != null && references.isNotEmpty) snapshot = snapshot.mergeReferenceData(references);
    return snapshot;
  }

  Future<Map<String, dynamic>> sendEvents(PrincipalConfig c, List<TeacherEvent> events) async {
    if (events.isEmpty) return {'received': 0, 'acknowledgedIds': <String>[]};
    final body = {
      'protocolVersion': supportedProtocol,
      'teacher': c.teacher,
      'events': events.map((e) => e.toProtocolV6Json()).toList(),
    };
    final r = await http.post(
      _uri(c, '/api/v1/events', {'teacher': c.teacher, 'code': c.code}),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    ).timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PrincipalApiException(
        'Transmission refusée (${r.statusCode}) : ${utf8.decode(r.bodyBytes).trim()}',
      );
    }
    if (r.bodyBytes.isEmpty) return {'received': events.length};
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {'received': events.length};
  }
}
