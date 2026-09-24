import 'dart:async';
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
  static const int defaultPort = 47831;
  static const String mobileVersion = '0.6.0';
  final Duration timeout;

  const PrincipalApi({this.timeout = const Duration(seconds: 8)});

  String get deviceName => 'Mobile ${Platform.operatingSystem}';

  Uri _uri(PrincipalConfig c, String path, [Map<String, String>? query]) =>
      Uri.parse('${c.baseUrl}$path').replace(queryParameters: query);

  Map<String, String> _authQuery(
    PrincipalConfig c,
    String deviceId, {
    Map<String, String>? extra,
  }) => {
    'teacher': c.teacher,
    if (c.principalId.isNotEmpty) 'principalId': c.principalId,
    'code': c.code,
    if (deviceId.trim().isNotEmpty) 'deviceId': deviceId.trim(),
    if (deviceId.trim().isNotEmpty) 'deviceName': deviceName,
    ...?extra,
  };

  Future<bool> ping(PrincipalConfig c) async {
    try {
      final r = await http.get(_uri(c, '/api/v1/ping')).timeout(timeout);
      return r.statusCode >= 200 && r.statusCode < 300;
    } on SocketException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<PrincipalConfig?> _pairHost(
    String host,
    String code, {
    required String deviceId,
    int port = defaultPort,
    Duration? pairTimeout,
  }) async {
    try {
      final uri = Uri.parse('http://$host:$port/api/v1/pair').replace(
        queryParameters: {
          'code': code,
          if (deviceId.trim().isNotEmpty) 'deviceId': deviceId.trim(),
          if (deviceId.trim().isNotEmpty) 'deviceName': deviceName,
        },
      );
      final r = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'GESTCOURS-Prof-Mobile/$mobileVersion',
            },
          )
          .timeout(pairTimeout ?? const Duration(milliseconds: 650));
      if (r.statusCode == 403) {
        throw PrincipalApiException(
          'Code professeur incorrect ou accès désactivé dans le Principal.',
        );
      }
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
        throw PrincipalApiException(
          'Le Principal répond, mais l’appairage a échoué (${r.statusCode}).',
        );
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map) return null;
      final data = Map<String, dynamic>.from(decoded);
      final ok = data['ok'] == true;
      final protocol =
          int.tryParse((data['protocolVersion'] ?? '0').toString()) ?? 0;
      final teacher = (data['teacher'] ?? '').toString().trim();
      final returnedPort =
          int.tryParse((data['port'] ?? port).toString()) ?? port;
      final authorized = data['deviceAuthorized'];
      if (protocol != supportedProtocol) {
        throw PrincipalApiException(
          'Versions incompatibles. Mettez à jour le Principal et le mobile ensemble.',
        );
      }
      if (!ok || teacher.isEmpty) {
        throw PrincipalApiException('Réponse du Principal invalide.');
      }
      if (authorized == false) {
        throw PrincipalApiException(
          'Cet appareil attend une autorisation ou est désactivé. Sur le Principal : Réseau enseignants > Appareils autorisés.',
        );
      }
      return PrincipalConfig(
        host: host,
        port: returnedPort,
        teacher: teacher,
        code: code,
        principalId: (data['principalId'] ?? '').toString(),
      );
    } on PrincipalApiException {
      rethrow;
    } on TimeoutException {
      throw PrincipalApiException(
        'Le PC Principal ne répond pas. Vérifiez le Wi-Fi, son adresse et le pare-feu Windows.',
      );
    } on SocketException {
      throw PrincipalApiException(
        'Réseau local inaccessible. Vérifiez le Wi-Fi et l’autorisation Réseau local.',
      );
    } on FormatException {
      throw PrincipalApiException(
        'La réponse reçue n’est pas une réponse GESTCOURS valide.',
      );
    }
  }

  Future<PrincipalConfig> pairAddress(
    String rawHost,
    String rawCode, {
    required String deviceId,
  }) async {
    final raw = rawHost.trim();
    final parsed = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (parsed == null ||
        parsed.scheme != 'http' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw PrincipalApiException(
        'Adresse invalide. Exemple : 192.168.1.20 ou 192.168.1.20:47831.',
      );
    }
    final host = parsed.host;
    final port = parsed.hasPort ? parsed.port : defaultPort;
    if (port < 1 || port > 65535) {
      throw PrincipalApiException('Le numéro de port est invalide.');
    }
    final code = rawCode.trim();
    if (host.isEmpty) {
      throw PrincipalApiException(
        'Saisissez l’adresse du PC Principal affichée dans GESTCOURS.',
      );
    }
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw PrincipalApiException('Saisissez le code professeur à 6 chiffres.');
    }
    final found = await _pairHost(
      host,
      code,
      deviceId: deviceId,
      port: port,
      pairTimeout: const Duration(seconds: 3),
    );
    if (found == null) {
      throw PrincipalApiException(
        'Connexion impossible à $host:$port. Vérifiez l’adresse affichée dans le Principal, le même Wi-Fi/réseau, le code professeur et l’autorisation Windows.',
      );
    }
    return found;
  }

  Future<Map<String, dynamic>?> _referenceData(
    PrincipalConfig c,
    String deviceId,
  ) async {
    try {
      final r = await http
          .get(
            _uri(c, '/api/v1/reference-data', _authQuery(c, deviceId)),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'GESTCOURS-Prof-Mobile/$mobileVersion',
            },
          )
          .timeout(timeout);
      if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<SyncSnapshot> sync(
    PrincipalConfig c, {
    required String deviceId,
  }) async {
    final r = await http
        .get(
          _uri(c, '/api/v1/sync', _authQuery(c, deviceId)),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'GESTCOURS-Prof-Mobile/$mobileVersion',
          },
        )
        .timeout(timeout);

    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = utf8.decode(r.bodyBytes).trim();
      if (r.statusCode == 403 && detail.toLowerCase().contains('appareil')) {
        throw PrincipalApiException(
          'Appareil non autorisé ou désactivé par le Principal.',
        );
      }
      if (r.statusCode == 403) {
        throw PrincipalApiException(
          'Code professeur refusé ou accès désactivé par le Principal.',
        );
      }
      throw PrincipalApiException(
        'Synchronisation refusée (${r.statusCode})${detail.isEmpty ? '' : ' : $detail'}',
      );
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is! Map) {
      throw PrincipalApiException('Réponse de synchronisation invalide.');
    }
    var snapshot = SyncSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    if (snapshot.protocolVersion != 0 &&
        snapshot.protocolVersion != supportedProtocol) {
      throw PrincipalApiException(
        'Version de protocole incompatible : Principal ${snapshot.protocolVersion}, mobile $supportedProtocol.',
      );
    }
    final references = await _referenceData(c, deviceId);
    if (references != null && references.isNotEmpty) {
      snapshot = snapshot.mergeReferenceData(references);
    }
    return snapshot;
  }

  Future<Map<String, dynamic>> sendEvents(
    PrincipalConfig c,
    List<TeacherEvent> events, {
    required String deviceId,
  }) async {
    if (events.isEmpty) return {'received': 0, 'acknowledgedIds': <String>[]};
    final body = {
      'protocolVersion': supportedProtocol,
      'teacher': c.teacher,
      if (c.principalId.isNotEmpty) 'principalId': c.principalId,
      'events': events.map((e) => e.toProtocolV6Json()).toList(),
    };
    final r = await http
        .post(
          _uri(c, '/api/v1/events', _authQuery(c, deviceId)),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'GESTCOURS-Prof-Mobile/$mobileVersion',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final detail = utf8.decode(r.bodyBytes).trim();
      if (r.statusCode == 403 && detail.toLowerCase().contains('appareil')) {
        throw PrincipalApiException(
          'Transmission bloquée : appareil non autorisé ou désactivé par le Principal.',
        );
      }
      throw PrincipalApiException(
        'Transmission refusée (${r.statusCode})${detail.isEmpty ? '' : ' : $detail'}',
      );
    }
    if (r.bodyBytes.isEmpty) return {'received': events.length};
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : {'received': events.length};
  }

  Future<Map<String, Map<String, String>>> eventStatuses(
    PrincipalConfig c,
    List<String> ids, {
    required String deviceId,
  }) async {
    if (ids.isEmpty) return const {};
    final limited = ids.where((e) => e.trim().isNotEmpty).take(100).toList();
    if (limited.isEmpty) return const {};
    final r = await http
        .get(
          _uri(
            c,
            '/api/v1/event-status',
            _authQuery(c, deviceId, extra: {'ids': limited.join(',')}),
          ),
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'GESTCOURS-Prof-Mobile/$mobileVersion',
          },
        )
        .timeout(timeout);
    if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) {
      throw PrincipalApiException(
        'Les décisions du Principal ne sont pas disponibles (${r.statusCode}).',
      );
    }
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is! Map || decoded['items'] is! List) return const {};
    final out = <String, Map<String, String>>{};
    for (final raw in decoded['items'] as List) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      out[id] = {
        'status': (item['status'] ?? 'received').toString(),
        'reviewNote': (item['reviewNote'] ?? '').toString(),
      };
    }
    return out;
  }
}
